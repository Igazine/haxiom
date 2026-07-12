package haxiom;

import haxiom.Lexer;
import haxiom.Parser;
import haxiom.Interp;
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
class Haxiom {
	/**
	 * The underlying interpreter instance carrying the execution scope, globals, and callbacks.
	 */
	public var interp:Interp;

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
	public var astCache:Map<String, haxiom.AST.Expr> = new Map();

	var astCacheSize:Int = 0;

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

	/**
	 * Optional callback triggered when a runtime or compile error occurs during script execution.
	 */
	public var errorHandler(get, set):Null<ScriptException->Void>;

	inline function get_errorHandler()
		return interp.errorHandler;

	inline function set_errorHandler(v)
		return interp.errorHandler = v;

	/**
	 * If true, Haxiom compiles the AST to bytecode and executes it via the HXBC virtual machine.
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
	 * Override parameter to force main execution routing to a specific class name.
	 */
	public var mainClassOverride:String = null;

	/**
	 * Contextual filename representing the active script execution path (used for error stack traces).
	 */
	public var currentFilename:String = null;

	/**
	 * Instantiates a new Haxiom scripting engine instance and registers core HFFI bindings.
	 */
	public function new() {
		interp = new Interp();
		FFI.exposedModules.set("haxiom.AST", ["haxiom.ExprDef", "haxiom.TypeDecl"]);
		FFI.registerEnum(this, "haxiom.ExprDef", haxiom.AST.ExprDef);
		FFI.registerEnum(this, "haxiom.TypeDecl", haxiom.AST.TypeDecl);
		FFI.registerClass(this, "haxiom.Future", haxiom.Future);
	}

	/**
	 * A placeholder helper to represent asynchronous fiber suspension in guest scripts.
	 * 
	 * @throws String If invoked directly in host Haxe code.
	 */
	public static function await<T>(future:Dynamic):T {
		throw "Haxiom.await() can only be used inside Haxiom guest scripts executing in the VM.";
	}

	/**
	 * Validates if the supplied package namespace string is a valid identifier path.
	 * Must contain only alphanumeric characters, underscores, and dots,
	 * and each dot-separated segment must start with a letter or underscore.
	 */
	public static function isValidNamespace(ns:String):Bool {
		if (ns == null || ns == "") return false;
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
	 * @param filename Optional filename path to associate with parsed symbols (used for error reporting).
	 * @return The optimized AST node root representation, or null if compilation failed.
	 */
	public function compile(source:String, ?filename:String, ?staticTypes:Bool = false, ?customPackage:String):haxiom.AST.Expr {
		if (customPackage != null) {
			if (!isValidNamespace(customPackage)) {
				throw "Invalid custom package namespace format: " + customPackage;
			}
			interp.currentPackage = customPackage.split(".");
		} else {
			interp.currentPackage = [];
		}
		if (enableAstCache && astCache.exists(source)) {
			var folded = astCache.get(source);
			if (staticTypes || enableStaticTypes) {
				haxiom.StaticTypeChecker.check(folded, interp);
			}
			return folded;
		}
		var fileInfo = filename != null ? filename : "script";
		var fileBaseName:String = null;
		if (filename != null && filename != "script") {
			var idx = filename.lastIndexOf("/");
			var idx2 = filename.lastIndexOf("\\");
			var clean = filename;
			if (idx != -1 || idx2 != -1) {
				var maxIdx = idx > idx2 ? idx : idx2;
				clean = filename.substring(maxIdx + 1);
			}
			var dotIdx = clean.indexOf(".");
			if (dotIdx != -1) {
				fileBaseName = clean.substring(0, dotIdx);
			} else {
				fileBaseName = clean;
			}
		}
		interp.lastSource = source;
		try {
			var lexer = new Lexer(source, fileInfo, interp.preprocessorFlags);
			var tokens = lexer.tokenize();
			var parser = new Parser(tokens, fileInfo);
			var ast = parser.parse();
			ast = appendMainCallIfPresent(ast, mainClassOverride != null ? mainClassOverride : fileBaseName);

			// Pass 1: Scan and register macro definitions in interpreter scope
			haxiom.MacroExpander.registerMacros(ast, interp);

			// Pass 2: Crawl AST and expand macro static calls
			ast = haxiom.MacroExpander.expand(ast, interp);

			var folded = Optimizer.foldConstants(ast);

			if (enableDCE) {
				folded = Optimizer.eliminateDeadCode(folded);
			}

			if (staticTypes || enableStaticTypes) {
				haxiom.StaticTypeChecker.check(folded, interp);
			}

			if (enableAstCache) {
				if (astCacheSize >= 1000) {
					astCache = new Map();
					astCacheSize = 0;
				}
				astCache.set(source, folded);
				astCacheSize++;
			}
			return folded;
		} catch (e:ScriptException) {
			if (errorHandler != null) {
				errorHandler(e);
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
			if (errorHandler != null) {
				errorHandler(se);
				return null;
			}
			throw se;
		} catch (err:Dynamic) {
			var se = new ScriptException(Std.string(err), [], "Compile Error: " + Std.string(err), 1, 1, fileInfo);
			if (errorHandler != null) {
				errorHandler(se);
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
	 * @param customPackage Optional custom package namespace to execute within.
	 * @return The computed return value from script execution.
	 */
	public function execute<T>(ast:haxiom.AST.Expr, ?customPackage:String):T {
		if (customPackage != null) {
			if (!isValidNamespace(customPackage)) {
				throw "Invalid custom package namespace format: " + customPackage;
			}
			interp.currentPackage = customPackage.split(".");
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
	 * @param onDone Optional callback invoked with the execution result upon success.
	 * @param staticTypes Enable compile-time static type checking.
	 * @param customPackage Optional custom package namespace to isolate classes compiled/executed.
	 * @return The computed execution result.
	 */
	public function interpret<T>(source:String, ?onDone:T->Void, ?staticTypes:Bool = false, ?customPackage:String):T {
		var ast = compile(source, currentFilename, staticTypes, customPackage);
		if (ast == null)
			return null;
		var result:T = execute(ast, customPackage);
		if (onDone != null)
			onDone(result);
		return result;
	}

	/**
	 * Compiles script source code into a serialized binary representation.
	 * Depending on `useVM`, generates either AST bytes or VM bytecode bytes.
	 * 
	 * @param source The script source code string.
	 * @param filename Optional filename path parameter.
	 * @param key Optional encryption key to obfuscate/secure the bytecode payload (VM mode only).
	 * @param debugMode If true, embeds variable symbol lifespan tables and positions (VM mode only).
	 * @return The serialized binary bytes representing the compiled output.
	 */
	public function compileToBytes(source:String, ?filename:String, ?key:HXBCKey, ?debugMode:Bool = false):haxe.io.Bytes {
		if (useVM) {
			return compileToBytecodeBytes(source, filename, key, debugMode);
		}
		return compileToASTBytes(source, filename);
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
	 * @param filename Optional filename path context.
	 * @return Serialized AST bytes.
	 */
	public function compileToASTBytes(source:String, ?filename:String):haxe.io.Bytes {
		var ast = compile(source, filename);
		if (ast == null)
			return null;
		return Serializer.serializeToBytes(ast);
	}

	/**
	 * Compiles and serializes a script into VM bytecode bytes (HXBC format).
	 * 
	 * @param source The script source code string.
	 * @param filename Optional filename path context.
	 * @param key Optional encryption key to obfuscate/secure the bytecode payload.
	 * @param debugMode If true, embeds debug symbols for local variables and positions.
	 * @return Serialized HXBC VM bytecode bytes.
	 */
	public function compileToBytecodeBytes(source:String, ?filename:String, ?key:HXBCKey, ?debugMode:Bool = false):haxe.io.Bytes {
		// In debug mode, disable DCE and the AST cache so all local variables are preserved
		// for debug symbol capture. The DCE'd (release) AST must not bleed through the cache.
		var prevDCE = enableDCE;
		var prevCache = enableAstCache;
		if (debugMode) {
			enableDCE = false;
			enableAstCache = false;
		}
		var ast = compile(source, filename);
		enableDCE = prevDCE;
		enableAstCache = prevCache;
		if (ast == null)
			return null;
		var chunk = BytecodeCompiler.compile(ast, null, true, false, debugMode);
		return Serializer.serializeBytecode(chunk, key);
	}

	public function compileASTToBytecodeBytes(ast:haxiom.AST.Expr, ?key:HXBCKey, ?debugMode:Bool = false):haxe.io.Bytes {
		if (ast == null)
			return null;
		var chunk = BytecodeCompiler.compile(ast, null, true, false, debugMode);
		return Serializer.serializeBytecode(chunk, key);
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
		var ast = Serializer.deserializeFromBytes(bytes);
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
		var chunk = Serializer.deserializeBytecode(bytes, key);
		return cast interp.executeChunk(chunk);
	}

	/**
	 * Exposes a host object or value as a global variable accessible to guest scripts.
	 * 
	 * @param name The global variable name to declare (e.g. `container`).
	 * @param value The host object reference or value.
	 */
	public function setGlobal(name:String, value:Dynamic):Void {
		interp.globals.declare(name, value);
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

	public static function appendMainCallIfPresent(expr:haxiom.AST.Expr, ?fileBaseName:String):haxiom.AST.Expr {
		var mainClasses:Array<String> = [];

		function checkExpr(e:haxiom.AST.Expr) {
			if (e == null)
				return;
			switch (e.def) {
				case EClass(name, _, methods, _, _, _, _):
					for (m in methods) {
						if (m.name == "main" && m.isStatic) {
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
		} else {
			mainClass = mainClasses[0];
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
			Context.error("Could not determine target interface type. Please specify it explicitly, e.g. construct(IPlugin, className) or via variable type annotation", className.pos);
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

	public static function registerInterface(haxiom:Haxiom, name:String):Void {
		FFI.registerValue(haxiom, name, {__isInterface: true});
	}

	public static function constructHelper(haxiom:Haxiom, className:String, factory:(Haxiom, Dynamic) -> Dynamic):Dynamic {
		var guestInst = haxiom.interpret("new " + className + "();");
		return factory(haxiom, guestInst);
	}
}
