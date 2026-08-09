package haxiom;

import haxiom.Lexer;
import haxiom.Parser;
import haxiom.Interp;
import haxiom.HXBCInfo;
import haxiom.HaxiomTypes.HaxiomClass;
import haxiom.HaxiomTypes.HaxiomInterface;
import haxiom.HaxiomTypes.HaxiomInstance;
import haxiom.HaxiomTypes.HaxiomEnum;
import haxiom.HaxiomTypes.HaxiomEnumInstance;
import haxiom.HaxiomTypes.HaxiomAbstract;
import haxiom.HaxiomTypes.HaxiomAbstractInstance;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
 * The main Haxiom scripting engine instance.
 * Provides APIs for compiling, interpreting, and executing scripts in either
 * AST interpretation mode or compiled Bytecode VM mode.
 */
@:allow(haxiom)
class Haxiom {
	/**
	 * The underlying interpreter instance carrying the execution scope, globals, and callbacks.
	 */
	var interp:Interp;

	/**
	 * If true, enables caching of compiled ASTs to speed up subsequent executions of identical script strings.
	 */
	public var enableAstCache:Bool = true;

	/**
	 * If true, applies a Dead Code Elimination (DCE) pass after constant folding during compilation.
	 * Removes unreachable statements, unused pure locals, and dead private methods.
	 * Enabled by default.
	 */
	public var enableDCE:Bool = true;

	/**
	 * If true, enables static type checking during compilation.
	 * By default, everything is dynamically typed (checking is opt-in).
	 */
	public var enableStaticTypes:Bool = false;

	/**
	 * Internal cache storing compiled AST nodes by their raw source code key.
	 */
	var astCache:Map<String, haxiom.AST.Expr> = new Map();

	var astCacheSize:Int = 0;

	function cachePart(value:String):String {
		if (value == null)
			return "0:";
		return Std.string(value.length) + ":" + value;
	}

	function makeAstCacheKey(source:String, ?context:ScriptContext):String {
		var flags = [for (name in interp.preprocessorFlags.keys()) name + "=" + (interp.preprocessorFlags.get(name) == true ? "1" : "0")];
		flags.sort(Reflect.compare);
		return cachePart(source)
			+ cachePart(context != null ? context.name : null)
			+ cachePart(resolveSourceLabel(context))
			+ cachePart(context != null ? context.packageName : null)
			+ cachePart(context != null && context.staticTypes == true ? "static=1" : "static=0")
			+ cachePart(enableDCE ? "dce=1" : "dce=0")
			+ cachePart(flags.join("|"));
	}

	static function resolveSourceLabel(?context:ScriptContext):String {
		if (context != null) {
			if (context.sourceLabel != null)
				return context.sourceLabel;
			if (context.name != null)
				return context.name;
		}
		return "script";
	}

	/**
	 * A callback invoked to resolve external dependency modules dynamically when an `import` statement is parsed.
	 * Maps a fully-qualified module path (e.g. `helper.MathUtils`) to its source code.
	 */
	public var moduleResolver(get, set):String->String;

	inline function get_moduleResolver()
		return interp.moduleResolver;

	inline function set_moduleResolver(v)
		return interp.moduleResolver = v;

	/**
	 * The whitelist array containing permitted class/package names that the guest script is authorized to resolve.
	 */
	public var importWhitelist(get, set):Array<String>;

	inline function get_importWhitelist()
		return interp.importWhitelist;

	inline function set_importWhitelist(v)
		return interp.importWhitelist = v;

	var _onCompilerError:Null<ScriptException->Void> = null;
	var _onRuntimeError:Null<ScriptException->Void> = null;

	/**
	 * Optional callback triggered when a compilation error occurs.
	 */
	public var onCompilerError(get, set):Null<ScriptException->Void>;

	inline function get_onCompilerError()
		return _onCompilerError;

	inline function set_onCompilerError(v) {
		_onCompilerError = v;
		updateInterpErrorHandler();
		return v;
	}

	/**
	 * Optional callback triggered when a runtime execution error occurs.
	 */
	public var onRuntimeError(get, set):Null<ScriptException->Void>;

	inline function get_onRuntimeError()
		return _onRuntimeError;

	inline function set_onRuntimeError(v) {
		_onRuntimeError = v;
		updateInterpErrorHandler();
		return v;
	}

	function updateInterpErrorHandler() {
		if (_onRuntimeError != null) {
			interp.onRuntimeError = (err:ScriptException) -> {
				var ns = err.runtimeNamespace != null ? err.runtimeNamespace : getActiveNamespace();
				if (ns != null) {
					interp.haltNamespace(ns);
				}
				_onRuntimeError(err);
			};
		} else {
			interp.onRuntimeError = null;
		}
	}

	function getActiveNamespace():Null<String> {
		if (interp.currentPackage != null && interp.currentPackage.length > 0) {
			return interp.currentPackage.join(".");
		}
		return null;
	}

	/**
	 * Queries whether a package namespace has been halted due to a runtime error.
	 */
	public function isNamespaceHalted(name:String):Bool {
		return interp.isNamespaceHalted(name);
	}

	/**
	 * Clears all halted namespace states.
	 */
	public function clearHaltedNamespaces():Void {
		interp.clearHaltedNamespaces();
	}

	/**
	 * If true (the default), Haxiom compiles the AST to bytecode and executes it via the HXBC virtual machine.
	 * If false, Haxiom evaluates the AST nodes recursively in interpretation mode.
	 */
	public var useVM(get, set):Bool;

	inline function get_useVM()
		return interp.useVM;

	inline function set_useVM(v)
		return interp.useVM = v;

	/**
	 * Read-only map of defined preprocessor flags currently active in the interpreter.
	 */
	public var preprocessorFlags(get, never):Map<String, Bool>;

	inline function get_preprocessorFlags()
		return interp.preprocessorFlags;

	/**
	 * Defines a custom preprocessor flag for script conditional compilation (#if name).
	 */
	public function setDefine(name:String, value:Bool = true):Void {
		interp.setDefine(name, value);
	}

	/**
	 * Removes a defined preprocessor flag.
	 */
	public function removeDefine(name:String):Void {
		interp.removeDefine(name);
	}

	/**
	 * Returns true if a preprocessor flag is defined.
	 */
	public function hasDefine(name:String):Bool {
		return interp.hasDefine(name);
	}

	/**
	 * Returns the boolean value of a defined preprocessor flag.
	 */
	public function getDefine(name:String):Bool {
		return interp.getDefine(name);
	}

	/**
	 * Returns the low-level lifecycle VMState of this engine instance.
	 */
	public var state(get, never):VMState;

	inline function get_state():VMState
		return interp.state;

	/**
	 * Resets halted error flags and resets the engine state to UNINITIALIZED.
	 */
	public function reset():Void {
		interp.reset();
	}

	/**
	 * Controls whether object/scope/frame pooling is enabled for this engine instance.
	 */
	public var enablePooling(get, set):Bool;

	inline function get_enablePooling()
		return interp.enablePooling;

	inline function set_enablePooling(v)
		return interp.enablePooling = v;

	/**
	 * If true, compiles scripts in debug mode, tracking source code coordinates for traces
	 * and generating debug symbol lifespans to output local variable values in error stack traces.
	 */
	public var debugMode(get, set):Bool;

	inline function get_debugMode()
		return interp.debugMode;

	inline function set_debugMode(v)
		return interp.debugMode = v;

	/**
	 * The maximum number of operations/instructions allowed per execution.
	 * Set to `0` to disable the safeguard / allow unlimited execution.
	 */
	public var maxInstructions(get, set):Int;

	inline function get_maxInstructions()
		return interp.maxInstructions;

	inline function set_maxInstructions(v)
		return interp.maxInstructions = v;

	/**
	 * The maximum memory allocation units allowed per execution.
	 * Set to `0` to disable the safeguard / allow unlimited memory.
	 */
	public var maxMemory(get, set):Int;

	inline function get_maxMemory()
		return interp.maxMemory;

	inline function set_maxMemory(v)
		return interp.maxMemory = v;

	/**
	 * Maximum encoded or decoded size accepted by persisted AST and HXBC loaders.
	 * Defaults to 64 MiB. Set to `0` to disable the size limit.
	 */
	public var maxPersistedBytes(get, set):Int;

	inline function get_maxPersistedBytes()
		return interp.maxPersistedBytes;

	inline function set_maxPersistedBytes(v)
		return interp.maxPersistedBytes = requireNonNegativeLimit(v, "maxPersistedBytes");

	/**
	 * Maximum JSON nesting accepted by the portable AST loader.
	 * Defaults to 512. Set to `0` to disable the depth limit.
	 */
	public var maxPersistedDepth(get, set):Int;

	inline function get_maxPersistedDepth()
		return interp.maxPersistedDepth;

	inline function set_maxPersistedDepth(v)
		return interp.maxPersistedDepth = requireNonNegativeLimit(v, "maxPersistedDepth");

	inline function requireNonNegativeLimit(value:Int, name:String):Int {
		if (value < 0)
			throw '$name cannot be negative';
		return value;
	}

	/**
	 * Identifies the active script caller (file, className, methodName, line, column)
	 * during an active FFI host function call. Returns `null` if the call originated natively from host code
	 * or if the engine is idle.
	 */
	public var currentCaller(get, never):Null<ScriptStackFrame>;

	inline function get_currentCaller():Null<ScriptStackFrame>
		return interp.getCallerInfo();

	/**
	 * Instantiates a new Haxiom scripting engine instance and registers core HFFI bindings.
	 */
	public function new() {
		interp = new Interp();
		registerClassRuntime("haxiom.guest.Future", haxiom.guest.Future);
		registerClassRuntime("haxiom.guest.HaxiomHost", haxiom.guest.HaxiomHost);
	}

	/**
	 * Validates if the supplied package namespace string is a valid identifier path.
	 * Must contain only alphanumeric characters, underscores, and dots,
	 * and each dot-separated segment must start with a letter or underscore.
	 */
	public static function isValidNamespace(ns:String):Bool {
		if (ns == null || ns == "")
			return false;
		var r = ~/^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$/;
		return r.match(ns);
	}

	/**
	 * Read-only status indicating whether this engine instance has been disposed.
	 */
	public var disposed(get, never):Bool;

	inline function get_disposed()
		return interp.disposed;

	/**
	 * Disposes of the engine instance, freeing all globals, scopes, AST caches, and aborting active fibers.
	 * A `Haxiom` instance should not be used after `dispose()` is called.
	 */
	public function dispose():Void {
		interp.dispose();
		astCache.clear();
		astCacheSize = 0;
	}

	/**
	 * Tokenizes, parses, expands macros, and optimizes a raw script string into a compiled Haxiom AST expression.
	 * 
	 * @param source The script source code string to compile.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @return The optimized AST node root representation, or null if compilation failed.
	 */
	public function compile(source:String, ?context:ScriptContext):haxiom.AST.Expr {
		var packageName = context != null ? context.packageName : null;
		var staticTypes = context != null && context.staticTypes == true;
		if (packageName != null) {
			if (!isValidNamespace(packageName)) {
				throw "Invalid package namespace format: " + packageName;
			}
			interp.currentPackage = packageName.split(".");
		} else {
			interp.currentPackage = [];
		}
		var cacheKey = makeAstCacheKey(source, context);
		if (enableAstCache && astCache.exists(cacheKey)) {
			var folded = astCache.get(cacheKey);
			if (staticTypes || enableStaticTypes) {
				haxiom.StaticTypeChecker.check(folded, interp);
			}
			return folded;
		}
		var fileInfo = resolveSourceLabel(context);
		var scriptName = context != null ? context.name : null;
		interp.lastSource = source;
		try {
			var lexer = new Lexer(source, fileInfo, interp.preprocessorFlags);
			var tokens = lexer.tokenize();
			var parser = new Parser(tokens, fileInfo);
			var ast = parser.parse();
			ast = appendMainCallIfPresent(ast, scriptName);

			// Pass 1: Scan and register macro definitions in interpreter scope
			haxiom.MacroExpander.registerMacros(ast, interp);

			// Pass 2: Crawl AST and expand macro static calls
			ast = haxiom.MacroExpander.expand(ast, interp);

			var folded = Optimizer.foldConstants(ast);

			if (staticTypes || enableStaticTypes) {
				haxiom.StaticTypeChecker.check(folded, interp);
			}

			if (enableDCE) {
				folded = Optimizer.eliminateDeadCode(folded);
			}

			if (enableAstCache) {
				if (astCacheSize >= 1000) {
					astCache = new Map();
					astCacheSize = 0;
				}
				astCache.set(cacheKey, folded);
				astCacheSize++;
			}
			return folded;
		} catch (e:ScriptException) {
			if (onCompilerError != null) {
				onCompilerError(e);
				return null;
			}
			throw e;
		} catch (e:CompileException) {
			var codeFrame = ScriptException.makeCodeFrame(source, e.line, e.col, e.file);
			var formatted = "Compile Error: " + e.message + " at " + e.file + ":" + e.line + ":" + e.col;
			if (codeFrame != "") {
				formatted += "\n" + codeFrame;
			}
			var se = new ScriptException(e.message, [], formatted, e.line, e.col, e.file);
			if (onCompilerError != null) {
				onCompilerError(se);
				return null;
			}
			throw se;
		} catch (err:Dynamic) {
			var se = new ScriptException(Std.string(err), [], "Compile Error: " + Std.string(err), 1, 1, fileInfo);
			if (onCompilerError != null) {
				onCompilerError(se);
				return null;
			}
			throw se;
		}
	}

	/**
	 * Executes a pre-compiled Haxiom AST expression tree and returns the computed result.
	 * Runs in VM mode if `useVM = true`, or AST evaluation mode if `useVM = false`.
	 * 
	 * @param ast The root AST node representation of the script to execute.
	 * @param context Optional package context to execute within.
	 * @return The computed return value from script execution.
	 */
	public function execute<T>(ast:haxiom.AST.Expr, ?context:ScriptContext):T {
		var packageName = context != null ? context.packageName : null;
		if (packageName != null) {
			if (!isValidNamespace(packageName)) {
				throw "Invalid package namespace format: " + packageName;
			}
			interp.currentPackage = packageName.split(".");
		} else {
			interp.currentPackage = [];
		}
		var result = interp.execute(ast);
		return cast result;
	}

	/**
	 * Compiles, parses, and evaluates a raw script string and returns the execution result.
	 * 
	 * @param source The raw script source code string to interpret.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @param onDone Optional callback invoked with the execution result upon success.
	 * @return The computed execution result.
	 */
	public function interpret<T>(source:String, ?context:ScriptContext, ?onDone:T->Void):T {
		var ast = compile(source, context);
		if (ast == null)
			return null;
		var result:T = execute(ast, context);
		if (onDone != null)
			onDone(result);
		return result;
	}

	/**
	 * Compiles script source code into a serialized binary representation.
	 * Depending on `useVM`, generates either AST bytes or VM bytecode bytes.
	 * 
	 * @param source The script source code string.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @param key Optional encryption key to obfuscate/secure the bytecode payload (VM mode only).
	 * @param debugMode Whether to embed variable symbols and positions in VM mode. Defaults to the engine's debug mode.
	 * @return The serialized binary bytes representing the compiled output.
	 */
	public function compileToBytes(source:String, ?context:ScriptContext, ?key:HXBCKey, ?debugMode:Null<Bool>):haxe.io.Bytes {
		if (useVM) {
			return compileToBytecodeBytes(source, context, key, debugMode != null ? debugMode : interp.debugMode);
		}
		return compileToASTBytes(source, context);
	}

	/**
	 * Deserializes and executes a pre-compiled binary script.
	 * Automatically routes to either VM execution or AST deserialization mode.
	 * 
	 * @param bytes The serialized binary bytes of the compiled script.
	 * @param sourceCode Optional original source code reference (used for displaying stack frames).
	 * @param key Optional key to decrypt the bytecode payload (must match compile key if compiled with encryption).
	 * @return The computed execution result.
	 */
	public function executeBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String, ?key:HXBCKey):T {
		if (useVM) {
			return executeBytecodeBytes(bytes, sourceCode, key);
		}
		return executeASTBytes(bytes, sourceCode);
	}

	/**
	 * Compiles and serializes a script into AST-based binary bytes.
	 * 
	 * @param source The script source code string.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @return Serialized AST bytes.
	 */
	public function compileToASTBytes(source:String, ?context:ScriptContext):haxe.io.Bytes {
		var prevDCE = enableDCE;
		var prevCache = enableAstCache;
		enableDCE = false;
		enableAstCache = false;
		var ast = try {
			compile(source, context);
		} catch (e:Dynamic) {
			enableDCE = prevDCE;
			enableAstCache = prevCache;
			throw e;
		}
		enableDCE = prevDCE;
		enableAstCache = prevCache;
		if (ast == null)
			return null;
		ast = embedASTResources(ast);
		return Serializer.serializeToBytes(ast);
	}

	function embedASTResources(expr:haxiom.AST.Expr):haxiom.AST.Expr {
		if (expr == null)
			return null;
		switch (expr.def) {
			case EValue(_) | EIdent(_) | EEReg(_, _) | EBreak | EContinue | EPackage(_) | EImport(_, _) | EUsing(_) | EEnum(_, _, _) | ETypedef(_, _):
				return expr;
			case EVar(name, type, e, isFinal, meta):
				var embedded = ResourceCompiler.processResource(interp, meta, type, e == null ? null : embedASTResources(e), expr.pos, null);
				expr.def = EVar(name, type, embedded, isFinal, stripResourceMeta(meta));
			case EAssign(target, e):
				expr.def = EAssign(embedASTResources(target), embedASTResources(e));
			case EBinop(op, e1, e2):
				expr.def = EBinop(op, embedASTResources(e1), embedASTResources(e2));
			case EUnop(op, e):
				expr.def = EUnop(op, embedASTResources(e));
			case EField(e, field):
				expr.def = EField(embedASTResources(e), field);
			case ESafeField(e, field):
				expr.def = ESafeField(embedASTResources(e), field);
			case ECall(e, args):
				expr.def = ECall(embedASTResources(e), embedASTResourceArray(args));
			case ENew(type, args):
				expr.def = ENew(type, embedASTResourceArray(args));
			case EArrayDecl(values):
				expr.def = EArrayDecl(embedASTResourceArray(values));
			case EObjectDecl(fields):
				expr.def = EObjectDecl([for (f in fields) {name: f.name, expr: embedASTResources(f.expr)}]);
			case EMapDecl(values):
				expr.def = EMapDecl([for (v in values) {key: embedASTResources(v.key), value: embedASTResources(v.value)}]);
			case EClass(name, fields, methods, parent, interfaces, params, meta, isExtern):
				expr.def = EClass(name, [
					for (f in fields)
						{
							name: f.name,
							type: f.type,
							expr: ResourceCompiler.processResource(interp, f.meta, f.type, f.expr == null ? null : embedASTResources(f.expr), expr.pos, null),
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							isFinal: f.isFinal,
							property: f.property,
							meta: stripResourceMeta(f.meta),
							isExtern: f.isExtern
						}
				], [
					for (m in methods)
						{
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: embedASTResources(m.body),
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							isOverride: m.isOverride,
							isAbstract: m.isAbstract,
							params: m.params,
							meta: m.meta,
							isExtern: m.isExtern
						}
				], parent, interfaces, params, meta, isExtern);
			case EAbstract(name, underlyingType, fields, methods, params, meta):
				expr.def = EAbstract(name, underlyingType, [
					for (f in fields)
						{
							name: f.name,
							type: f.type,
							expr: ResourceCompiler.processResource(interp, f.meta, f.type, f.expr == null ? null : embedASTResources(f.expr), expr.pos, null),
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							isFinal: f.isFinal,
							property: f.property,
							meta: stripResourceMeta(f.meta)
						}
				], [
					for (m in methods)
						{
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: embedASTResources(m.body),
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							params: m.params,
							meta: m.meta
						}
				], params, meta);
			case EInterface(name, fields, methods, parents, params, meta):
				expr.def = EInterface(name, fields, [
					for (m in methods)
						{
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: embedASTResources(m.body),
							params: m.params,
							meta: m.meta
						}
				], parents, params, meta);
			case EBlock(exprs):
				expr.def = EBlock(embedASTResourceArray(exprs));
			case EFunction(name, args, retType, body, params):
				expr.def = EFunction(name, args, retType, embedASTResources(body), params);
			case EIf(cond, e1, e2):
				expr.def = EIf(embedASTResources(cond), embedASTResources(e1), embedASTResources(e2));
			case EWhile(cond, e):
				expr.def = EWhile(embedASTResources(cond), embedASTResources(e));
			case EDoWhile(cond, e):
				expr.def = EDoWhile(embedASTResources(cond), embedASTResources(e));
			case EFor(v, it, e):
				expr.def = EFor(v, embedASTResources(it), embedASTResources(e));
			case ESwitch(switchExpr, cases, defExpr):
				expr.def = ESwitch(embedASTResources(switchExpr), [
					for (c in cases)
						{values: embedASTResourceArray(c.values), guard: embedASTResources(c.guard), expr: embedASTResources(c.expr)}
				], embedASTResources(defExpr));
			case EReturn(e):
				expr.def = EReturn(embedASTResources(e));
			case EThrow(e):
				expr.def = EThrow(embedASTResources(e));
			case ETry(tryExpr, catches):
				expr.def = ETry(embedASTResources(tryExpr), [
					for (c in catches)
						{pattern: embedASTResources(c.pattern), type: c.type, guard: embedASTResources(c.guard), body: embedASTResources(c.body)}
				]);
			case ECast(e, type):
				expr.def = ECast(embedASTResources(e), type);
			case EMeta(meta, e):
				expr.def = EMeta(meta, embedASTResources(e));
		}
		return expr;
	}

	function embedASTResourceArray(values:Array<haxiom.AST.Expr>):Array<haxiom.AST.Expr> {
		return values == null ? null : [for (v in values) embedASTResources(v)];
	}

	function stripResourceMeta(meta:Null<Array<{name:String, params:Array<haxiom.AST.Expr>}>>):Null<Array<{name:String, params:Array<haxiom.AST.Expr>}>> {
		if (meta == null)
			return null;
		var filtered = [
			for (m in meta)
				if (m == null || (m.name != ":haxiom.resource" && m.name != "haxiom.resource" && m.name != "@:haxiom.resource"))
					m
		];
		return filtered.length == 0 ? null : filtered;
	}

	/**
	 * Compiles and serializes a script into VM bytecode bytes (HXBC format).
	 * 
	 * @param source The script source code string.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @param key Optional encryption key to obfuscate/secure the bytecode payload.
	 * @param debugMode If true, embeds debug symbols for local variables and positions.
	 * @return Serialized HXBC VM bytecode bytes.
	 */
	public function compileToBytecodeBytes(source:String, ?context:ScriptContext, ?key:HXBCKey, ?debugMode:Bool = false, ?compress:Bool = false):haxe.io.Bytes {
		// In debug mode, disable DCE and the AST cache so all local variables are preserved
		// for debug symbol capture. The DCE'd (release) AST must not bleed through the cache.
		var prevDCE = enableDCE;
		var prevCache = enableAstCache;
		if (debugMode) {
			enableDCE = false;
			enableAstCache = false;
		}
		var ast = try {
			compile(source, context);
		} catch (e:Dynamic) {
			enableDCE = prevDCE;
			enableAstCache = prevCache;
			throw e;
		}
		enableDCE = prevDCE;
		enableAstCache = prevCache;
		if (ast == null)
			return null;
		var chunk = BytecodeCompiler.compile(ast, null, true, false, debugMode, null, interp, resolveSourceLabel(context));
		return Serializer.serializeBytecode(chunk, key, compress);
	}

	/**
	 * Compiles and serializes an existing AST expression tree directly into VM bytecode bytes.
	 * 
	 * @param ast The root AST node representation of the script.
	 * @param context Optional logical identity and compilation settings for this script.
	 * @param key Optional encryption key to obfuscate/secure the bytecode payload.
	 * @param debugMode If true, embeds debug symbols for local variables and positions.
	 * @param compress If true, applies LZ4 compression to the serialized bytecode payload.
	 * @return Serialized HXBC VM bytecode bytes.
	 */
	public function compileASTToBytecodeBytes(ast:haxiom.AST.Expr, ?context:ScriptContext, ?key:HXBCKey, ?debugMode:Bool = false,
			?compress:Bool = false):haxe.io.Bytes {
		if (ast == null)
			return null;
		var chunk = BytecodeCompiler.compile(ast, null, true, false, debugMode, null, interp, resolveSourceLabel(context));
		return Serializer.serializeBytecode(chunk, key, compress);
	}

	/**
	 * Deserializes and executes AST-based binary bytes.
	 * 
	 * @param bytes Serialized AST bytes.
	 * @param sourceCode Optional original source code reference.
	 * @return The computed execution result.
	 */
	public function executeASTBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String):T {
		if (sourceCode != null) {
			interp.lastSource = sourceCode;
		}
		var ast = Serializer.deserializeFromBytes(bytes, interp.maxPersistedBytes, interp.maxPersistedDepth);
		var oldUseVM = interp.useVM;
		interp.useVM = false;
		try {
			var result = execute(ast);
			interp.useVM = oldUseVM;
			return cast result;
		} catch (e:Dynamic) {
			interp.useVM = oldUseVM;
			throw e;
		}
	}

	/**
	 * Deserializes and executes VM bytecode bytes (HXBC format).
	 * 
	 * @param bytes Serialized VM bytecode bytes.
	 * @param sourceCode Optional original source code reference.
	 * @param key Optional key to decrypt the bytecode payload.
	 * @return The computed execution result.
	 */
	public function executeBytecodeBytes<T>(bytes:haxe.io.Bytes, ?sourceCode:String, ?key:HXBCKey):T {
		if (sourceCode != null) {
			interp.lastSource = sourceCode;
		}
		var chunk = Serializer.deserializeBytecode(bytes, key, interp.maxPersistedBytes);
		return cast interp.executeChunk(chunk);
	}

	/**
	 * Inspects compiled HXBC bytecode bytes before execution.
	 * Extracts binary metadata, compression ratio, RAM slot requirements,
	 * included source files, and declared classes/methods without running code.
	 * 
	 * @param bytes Serialized HXBC bytecode bytes.
	 * @param key Optional decryption key if bytecode payload is encrypted.
	 * @return Strongly-typed HXBCInfo structure containing metadata and analysis.
	 */
	public static function inspectBytecode(bytes:haxe.io.Bytes, ?key:HXBCKey, ?maxPersistedBytes:Int = 64 * 1024 * 1024):HXBCInfo {
		if (bytes == null || bytes.length < 18) {
			return {
				fileSize: bytes != null ? bytes.length : 0,
				uncompressedPayloadSize: 0,
				compressionRatioPct: 0.0,
				version: 0,
				maxSlots: 0,
				isAsync: false,
				isEncrypted: false,
				isCompressed: false,
				checksum: "0x0",
				status: "TOO_SHORT",
				error: "Invalid bytecode: data too short (minimum 18-byte header required)"
			};
		}

		var input = new haxe.io.BytesInput(bytes);
		input.bigEndian = false;
		var magic = input.readString(4);
		if (magic != "HXBC") {
			return {
				fileSize: bytes.length,
				uncompressedPayloadSize: 0,
				compressionRatioPct: 0.0,
				version: 0,
				maxSlots: 0,
				isAsync: false,
				isEncrypted: false,
				isCompressed: false,
				checksum: "0x0",
				status: "INVALID_MAGIC",
				error: 'Invalid magic header: ${magic} (expected "HXBC")'
			};
		}

		var version = input.readByte();
		var flags = input.readByte();
		var isAsync = (flags & 1) == 1;
		var isEncrypted = (flags & 2) == 2;
		var isCompressed = (flags & 4) == 4;
		var maxSlots = input.readInt32();
		var uncompressedSize = input.readInt32();
		var checksum = input.readInt32();
		var checksumHex = '0x' + StringTools.hex(checksum, 8);

		var payloadCompressedSize = bytes.length - 18;
		var savingPct = (isCompressed && uncompressedSize > 0) ? Math.round((1.0 - (payloadCompressedSize / uncompressedSize)) * 1000) / 10.0 : 0.0;

		var info:HXBCInfo = {
			fileSize: bytes.length,
			uncompressedPayloadSize: uncompressedSize,
			compressionRatioPct: savingPct,
			version: version,
			maxSlots: maxSlots,
			isAsync: isAsync,
			isEncrypted: isEncrypted,
			isCompressed: isCompressed,
			checksum: checksumHex,
			status: "VALID"
		};

		if (isEncrypted && (key == null || !key.isValid())) {
			info.status = "ENCRYPTED";
			info.error = "Payload is encrypted. Provide decryption key to inspect internal payload details.";
			return info;
		}

		try {
			var chunk = Serializer.deserializeBytecode(bytes, key, maxPersistedBytes);
			info.instructionCount = chunk.instructions != null ? chunk.instructions.length : 0;
			info.constantPoolSize = chunk.constants != null ? chunk.constants.length : 0;
			info.debugSymbolCount = chunk.debugSymbols != null ? chunk.debugSymbols.length : 0;
			info.positionMappingCount = chunk.positions != null ? chunk.positions.length : 0;
			info.scriptName = chunk.scriptName;
			info.debugSymbols = chunk.debugSymbols != null ? chunk.debugSymbols.map(s -> {
				slot: s.slot,
				name: s.name,
				startIp: s.startIp,
				endIp: s.endIp
			}) : [];

			// Source files extraction
			var filesMap = new Map<String, Bool>();
			var sourceFiles = [];
			if (chunk.positions != null) {
				for (p in chunk.positions) {
					if (p != null && p.file != null && p.file.length > 0) {
						if (!filesMap.exists(p.file)) {
							filesMap.set(p.file, true);
							sourceFiles.push(p.file);
						}
					}
				}
			}
			info.sourceFiles = sourceFiles;

			// Compiled types extraction
			var compiledTypes:Array<HXBCCompiledType> = [];
			if (chunk.constants != null) {
				for (c in chunk.constants) {
					if (c != null && Reflect.hasField(c, "def")) {
						var e:AST.Expr = cast c;
						switch (e.def) {
							case EPackage(path):
								compiledTypes.push({kind: "package", name: path.join(".")});

							case EClass(name, fields, methods, parent, interfaces, params, meta):
								var parentName:String = null;
								if (parent != null) {
									switch (parent) {
										case TPath(pPath, _): parentName = pPath.join(".");
										default:
									}
								}
								var itfNames = [];
								if (interfaces != null && interfaces.length > 0) {
									for (itf in interfaces) {
										switch (itf) {
											case TPath(iPath, _): itfNames.push(iPath.join("."));
											default:
										}
									}
								}
								var mNames = [for (m in methods) m.name];
								compiledTypes.push({
									kind: "class",
									name: name,
									parent: parentName,
									interfaces: itfNames,
									fieldCount: fields.length,
									methodCount: methods.length,
									methods: mNames
								});

							case EInterface(name, fields, methods, parents, params, meta):
								compiledTypes.push({
									kind: "interface",
									name: name,
									methodCount: methods.length,
									methods: [for (m in methods) m.name]
								});

							case EEnum(name, constructors, params):
								compiledTypes.push({
									kind: "enum",
									name: name,
									constructorCount: constructors.length,
									constructors: [for (ctor in constructors) ctor.name]
								});

							case EAbstract(name, underlyingType, fields, methods, params, meta):
								compiledTypes.push({
									kind: "abstract",
									name: name,
									fieldCount: fields.length,
									methodCount: methods.length
								});

							case ETypedef(name, type, params):
								compiledTypes.push({
									kind: "typedef",
									name: name
								});

							default:
						}
					}
				}
			}
			info.compiledTypes = compiledTypes;

			// Embedded resources extraction
			var embeddedRes:Array<{path:String, size:Int}> = [];
			if (chunk.resources != null) {
				for (k => v in chunk.resources) {
					embeddedRes.push({path: k, size: v != null ? v.length : 0});
				}
			}
			info.embeddedResources = embeddedRes;
		} catch (e:Dynamic) {
			info.status = "CORRUPTED";
			info.error = 'Error deserializing payload: ${e}';
		}

		return info;
	}

	/**
	 * Instance helper to inspect compiled HXBC bytecode bytes before execution.
	 */
	public inline function inspect(bytes:haxe.io.Bytes, ?key:HXBCKey):HXBCInfo {
		return inspectBytecode(bytes, key, interp.maxPersistedBytes);
	}

	/**
	 * Registers an in-memory virtual resource asset accessible to `@:haxiom.resource('./path')`.
	 */
	public function addResource(path:String, bytes:haxe.io.Bytes):Void {
		interp.virtualResources.set(path, bytes);
	}

	/**
	 * Sets a custom host resource provider function for resolving `@:haxiom.resource` items.
	 */
	public function setResourceProvider(provider:(path:String) -> haxe.io.Bytes):Void {
		interp.resourceProvider = provider;
	}

	/**
	 * Sets a custom security filter callback to intercept and block unauthorized property/field access on host objects.
	 * Return false to deny access (throws Security Error), or true to allow.
	 */
	public function setFieldAccessFilter(filter:(target:Dynamic, field:String) -> Bool):Void {
		interp.fieldAccessFilter = filter;
	}

	/**
	 * Exposes a host object or value as a global variable accessible to guest scripts.
	 * 
	 * @param name The global variable name to declare (e.g. `container`).
	 * @param value The host object reference or value.
	 * @param isMutable If true, allows guest scripts to modify the global variable (defaults to false).
	 */
	public function setGlobal(name:String, value:Dynamic, ?isMutable:Bool = false):Void {
		interp.globals.declare(name, value, null, !isMutable);
	}

	/**
	 * Retrieves a global variable or class reference by its name.
	 * 
	 * @param name The global variable or class name.
	 * @return The global value, class definition, or null if not found.
	 */
	public function getGlobal(name:String):Dynamic {
		return interp.globals.get(name);
	}

	/**
	 * Resolves a field or method closure on any object reference (class, instance, or host object).
	 * 
	 * @param target The target object or class metadata.
	 * @param field The field or method name to resolve.
	 * @return The resolved value or method closure.
	 */
	public function resolveField(target:Dynamic, field:String):Dynamic {
		return interp.evalField(target, field, interp.globals, {line: 1, col: 1, file: "host"});
	}

	static function appendMainCallIfPresent(expr:haxiom.AST.Expr, ?fileBaseName:String):haxiom.AST.Expr {
		var mainClasses:Array<String> = [];

		function checkExpr(e:haxiom.AST.Expr) {
			if (e == null)
				return;
			switch (e.def) {
				case EClass(name, _, methods, _, _, _, _):
					for (m in methods) {
						if (m.name == "main" && m.isPublic && m.isStatic && m.args.length == 0) {
							mainClasses.push(name);
							break;
						}
					}
				case EBlock(exprs):
					for (child in exprs) {
						checkExpr(child);
					}
				default:
			}
		}

		checkExpr(expr);
		if (mainClasses.length == 0)
			return expr;

		var mainClass:String = null;
		if (fileBaseName != null) {
			for (mc in mainClasses) {
				if (mc == fileBaseName) {
					mainClass = mc;
					break;
				}
			}
		}

		if (mainClass == null)
			return expr;

		var hasExistingCall = false;
		function checkForCall(e:haxiom.AST.Expr) {
			if (e == null)
				return;
			switch (e.def) {
				case ECall(sub, _):
					switch (sub.def) {
						case EField(ident, field):
							if (field == "main") {
								switch (ident.def) {
									case EIdent(name):
										if (name == mainClass) {
											hasExistingCall = true;
										}
									default:
								}
							}
						default:
					}
				case EBlock(exprs):
					for (child in exprs) {
						checkForCall(child);
					}
				default:
			}
		}
		checkForCall(expr);

		if (!hasExistingCall) {
			var pos = expr.pos;
			var identExpr:haxiom.AST.Expr = {def: EIdent(mainClass), pos: pos};
			var fieldExpr:haxiom.AST.Expr = {def: EField(identExpr, "main"), pos: pos};
			var callExpr:haxiom.AST.Expr = {def: ECall(fieldExpr, []), pos: pos};

			switch (expr.def) {
				case EBlock(exprs):
					exprs.push(callExpr);
					return expr;
				default:
					return {def: EBlock([expr, callExpr]), pos: pos};
			}
		}

		return expr;
	}

	/**
	 * Sets a field or property on any object reference (class, instance, or host object).
	 * 
	 * @param target The target object or class metadata.
	 * @param field The field or property name to set.
	 * @param value The value to assign.
	 */
	public function setField(target:Dynamic, field:String, value:Dynamic):Void {
		if (target != null && Std.isOfType(target, HaxiomInstance)) {
			var inst:HaxiomInstance = cast target;
			var setterName = "set_" + field;
			var setter = interp.findMethod(inst.cls, setterName);
			if (setter != null) {
				var func = interp.bindMethod(inst, setter);
				Reflect.callMethod(null, func, [value]);
			} else {
				inst.fields.set(field, value);
			}
		} else {
			Reflect.setProperty(target, field, value);
		}
	}

	/**
	 * Compile-time macro to construct and cast a guest class instance to a host-defined interface dynamically.
	 * 
	 * @param scriptPath The relative or absolute path to the guest script.
	 * @return An instance of the generated compile-time proxy implementing the expected interface.
	 */
	public macro function construct<T>(ethis:Expr, arg1:Expr, ?arg2:Expr):haxe.macro.Expr.ExprOf<T> {
		var expectedType = Context.getExpectedType();
		var targetInterface:Type = null;
		var className:Expr = null;

		if (arg2 == null) {
			// Case 1: haxiom.construct(className)
			className = arg1;

			if (expectedType != null) {
				switch (Context.follow(expectedType)) {
					case TInst(tRef, _):
						var t = tRef.get();
						if (t.isInterface) {
							targetInterface = expectedType;
						}
					default:
				}
			}
		} else {
			// Case 2: haxiom.construct(targetInterfaceExpr, className)
			className = arg2;
			var typeName = haxe.macro.ExprTools.toString(arg1);
			try {
				targetInterface = Context.getType(typeName);
			} catch (e:Dynamic) {
				Context.error("Could not resolve target interface type: " + typeName, arg1.pos);
			}
		}

		if (targetInterface == null || haxe.macro.TypeTools.toString(targetInterface) == "Dynamic") {
			Context.error("Could not determine target interface type. Please specify it explicitly, e.g. construct(IPlugin, className) or via variable type annotation",
				className.pos);
		}

		var expectedTypeStr:String = null;
		switch (Context.follow(targetInterface)) {
			case TInst(tRef, _):
				var t = tRef.get();
				if (t.isInterface) {
					expectedTypeStr = t.pack.join(".") + (t.pack.length > 0 ? "." : "") + t.name;
				}
			default:
		}

		var registerExprs = [];
		if (expectedTypeStr != null) {
			registerExprs.push(macro Haxiom.registerInterface($ethis, $v{expectedTypeStr}));
		}

		var proxyFqName = haxiom.macro.ProxyGenerator.generateProxy(targetInterface);
		var proxyTypePath = {pack: ["haxiom", "proxies"], name: proxyFqName.split(".").pop()};
		var targetInterfaceComplexType = Context.toComplexType(targetInterface);

		return macro {
			$b{registerExprs};
			(cast Haxiom.constructHelper($ethis, $className, function(h, guest) {
				return new $proxyTypePath(h, guest);
			}) : $targetInterfaceComplexType);
		};
	}

	/**
	 * Internal helper invoked by generated proxy macros to register a host interface via FFI.
	 * 
	 * @param haxiom The scripting engine instance.
	 * @param name The fully-qualified name of the interface.
	 */
	public static function registerInterface(haxiom:Haxiom, name:String):Void {
		haxiom.registerValue(name, {__isInterface: true});
	}

	/**
	 * Internal helper invoked by generated proxy macros to instantiate a guest class and wrap it inside a host proxy.
	 * 
	 * @param haxiom The scripting engine instance.
	 * @param className The guest class name to instantiate.
	 * @param factory A callback factory generating the host proxy instance.
	 * @return The generated host proxy implementing the target interface.
	 */
	public static function constructHelper(haxiom:Haxiom, className:String, factory:(Haxiom, Dynamic) -> Dynamic):Dynamic {
		var guestInst = haxiom.interpret("new " + className + "();");
		return factory(haxiom, guestInst);
	}

	public function registerMemberResolver(resolver:(obj:Dynamic, field:String) -> Dynamic):Void {
		interp.ffi.registerMemberResolver(resolver);
	}

	public function registerMemberAssigner(assigner:(obj:Dynamic, field:String, val:Dynamic) -> Bool):Void {
		interp.ffi.registerMemberAssigner(assigner);
	}

	public function registerStaticField(className:String, fieldName:String, value:Dynamic):Void {
		interp.ffi.registerStaticField(className, fieldName, value);
	}

	public function registerModule(moduleName:String, types:Array<String>):Void {
		interp.ffi.exposedModules.set(moduleName, types);
	}

	public function registerClassRuntime(fqName:String, cls:Class<Dynamic>):Void {
		interp.registerFullyQualified(fqName, cls, interp.globals);
		var realClassName = Type.getClassName(cls);
		if (realClassName != null && interp.importWhitelist != null && interp.importWhitelist.indexOf(realClassName) == -1) {
			interp.importWhitelist.push(realClassName);
		}
		if (interp.importWhitelist != null && interp.importWhitelist.indexOf(fqName) == -1) {
			interp.importWhitelist.push(fqName);
		}
		var parts = fqName.split(".");
		var shortName = parts[parts.length - 1];
		if (!interp.globals.exists(shortName)) {
			interp.globals.declare(shortName, cls);
		}
	}

	/** Unified API Aliases **/
	/** Expose a host class to scripts (alias for registerClass) */
	public inline function exposeClass(fqName:String, cls:Class<Dynamic>):Void {
		registerClassRuntime(fqName, cls);
	}

	/** Expose a host enum to scripts (alias for registerEnum) */
	public inline function exposeEnum(fqName:String, enm:Enum<Dynamic>):Void {
		registerEnum(fqName, enm);
	}

	/** Expose a host value or global to scripts (alias for registerValue) */
	public inline function exposeValue(fqName:String, value:Dynamic):Void {
		registerValue(fqName, value);
	}

	/** Expose / Whitelist an entire package pattern (e.g. "motion.*" or "openfl.*") */
	public inline function exposePackage(packagePattern:String):Void {
		allowPackage(packagePattern);
	}

	public function registerGenericInstantiation(signature:String, cls:Class<Dynamic>):Void {
		interp.ffi.exposedGenerics.set(signature, Type.getClassName(cls));
		interp.registerFullyQualified(signature, cls, interp.globals);
		if (interp.importWhitelist != null && interp.importWhitelist.indexOf(signature) == -1) {
			interp.importWhitelist.push(signature);
		}
	}

	public function registerEnum(fqName:String, enm:Enum<Dynamic>):Void {
		interp.registerFullyQualified(fqName, enm, interp.globals);
		if (interp.importWhitelist != null && interp.importWhitelist.indexOf(fqName) == -1) {
			interp.importWhitelist.push(fqName);
		}
		var parts = fqName.split(".");
		var shortName = parts[parts.length - 1];
		if (!interp.globals.exists(shortName)) {
			interp.globals.declare(shortName, enm);
		}
	}

	public function registerValue(fqName:String, value:Dynamic):Void {
		interp.registerFullyQualified(fqName, value, interp.globals);
		if (interp.importWhitelist != null && interp.importWhitelist.indexOf(fqName) == -1) {
			interp.importWhitelist.push(fqName);
		}
		var parts = fqName.split(".");
		var shortName = parts[parts.length - 1];
		if (!interp.globals.exists(shortName)) {
			interp.globals.declare(shortName, value);
		}
	}

	/**
	 * Whitelists a package pattern (e.g. "motion.actuators.*") for script field access.
	 */
	public function allowPackage(packagePattern:String):Void {
		if (interp.importWhitelist != null && interp.importWhitelist.indexOf(packagePattern) == -1) {
			interp.importWhitelist.push(packagePattern);
		}
	}

	public function registerExposedClasses():Void {
		#if !macro
		// 1. Load exposed classes
		var res = haxe.Resource.getString("haxiom_exposed_classes");
		if (res != null) {
			var list:Array<String> = haxe.Json.parse(res);
			for (fqName in list) {
				var cls = Type.resolveClass(fqName);
				if (cls != null) {
					registerClassRuntime(fqName, cls);
				}
			}
		}

		var staticFieldsRes = haxe.Resource.getString("haxiom_exposed_static_fields");
		if (staticFieldsRes != null) {
			var obj:Dynamic = haxe.Json.parse(staticFieldsRes);
			for (className in Reflect.fields(obj)) {
				var fieldsObj:Dynamic = Reflect.field(obj, className);
				for (fieldName in Reflect.fields(fieldsObj)) {
					registerStaticField(className, fieldName, Reflect.field(fieldsObj, fieldName));
				}
			}
		}

		// 2. Load exposed abstracts
		var absRes = haxe.Resource.getString("haxiom_exposed_abstracts");
		if (absRes != null) {
			var obj:Dynamic = haxe.Json.parse(absRes);
			for (k in Reflect.fields(obj)) {
				interp.ffi.exposedAbstracts.set(k, Reflect.field(obj, k));
			}
		}

		// 2b. Load runtime abstract implementation references
		var registryCls = Type.resolveClass("haxiom.macro.AbstractRegistry");
		if (registryCls != null) {
			var impls:Map<String, Dynamic> = Reflect.field(registryCls, "impls");
			if (impls != null) {
				for (k in impls.keys()) {
					interp.ffi.abstractImpls.set(k, impls.get(k));
				}
			}
		}

		// 3. Load exposed generics
		var genRes = haxe.Resource.getString("haxiom_exposed_generics");
		if (genRes != null) {
			var obj:Dynamic = haxe.Json.parse(genRes);
			for (k in Reflect.fields(obj)) {
				interp.ffi.exposedGenerics.set(k, Reflect.field(obj, k));
			}
		}

		// 4. Load exposed modules
		var modRes = haxe.Resource.getString("haxiom_exposed_modules");
		if (modRes != null) {
			var obj:Dynamic = haxe.Json.parse(modRes);
			for (k in Reflect.fields(obj)) {
				var arr:Array<Dynamic> = Reflect.field(obj, k);
				interp.ffi.exposedModules.set(k, [for (item in arr) Std.string(item)]);
			}
		}
		#end
	}

	public macro function registerClass(selfExpr:haxe.macro.Expr, fqNameExpr:haxe.macro.Expr.ExprOf<String>, classExpr:haxe.macro.Expr) {
		#if macro
		var className = haxe.macro.ExprTools.toString(classExpr);
		var t = null;
		try {
			t = haxe.macro.Context.getType(className);
		} catch (e:Dynamic) {}

		var exprs:Array<haxe.macro.Expr> = [];
		exprs.push(macro $selfExpr.registerClassRuntime($fqNameExpr, $classExpr));

		if (t != null) {
			switch (t) {
				case TInst(classRef, _):
					var c = classRef.get();
					for (field in c.statics.get()) {
						if (field.isPublic) {
							var isReadable = true;
							switch (field.kind) {
								case FVar(read, _):
									switch (read) {
										case AccNo | AccNever:
											isReadable = false;
										default:
									}
								default:
							}
							if (isReadable) {
								var fieldName = field.name;
								exprs.push(macro $selfExpr.registerStaticField($fqNameExpr, $v{fieldName}, $classExpr.$fieldName));
							}
						}
					}
				default:
			}
		}
		return macro {$a{exprs}};
		#else
		return macro null;
		#end
	}
}
