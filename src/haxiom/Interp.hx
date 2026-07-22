package haxiom;

import haxiom.AST;

enum ControlFlow {
	Return(val:Dynamic);
	Break;
	Continue;
}

@:allow(haxiom)
class Scope {
	var variables:Map<String, Dynamic> = new Map();
	var types:Map<String, TypeDecl> = new Map();
	var finals:Map<String, Bool> = new Map();
	var parent:Scope;
	var isCaptured:Bool = false;
	var isInPool:Bool = false;

	static var pool:Array<Scope> = [];

	static function create(?parent:Scope):Scope {
		if (pool.length > 0) {
			var s = pool.pop();
			s.parent = parent;
			s.isCaptured = false;
			s.isInPool = false;
			return s;
		}
		return new Scope(parent);
	}

	static function recycle(s:Scope):Void {
		if (s == null || s.isCaptured)
			return;
		if (s.isInPool)
			return;
		s.variables.clear();
		s.types.clear();
		s.finals.clear();
		s.parent = null;
		s.isCaptured = false;
		s.isInPool = true;
		pool.push(s);
	}

	function markCaptured():Void {
		if (isCaptured)
			return;
		isCaptured = true;
		if (parent != null) {
			parent.markCaptured();
		}
	}

	function new(?parent:Scope) {
		this.parent = parent;
	}

	function get(name:String):Dynamic {
		if (variables.exists(name))
			return variables.get(name);
		if (parent != null)
			return parent.get(name);
		return null;
	}

	function exists(name:String):Bool {
		if (variables.exists(name))
			return true;
		if (parent != null)
			return parent.exists(name);
		return false;
	}

	function set(name:String, val:Dynamic):Void {
		if (finals.get(name) == true) {
			throw 'Cannot reassign final variable $name';
		}
		if (variables.exists(name)) {
			variables.set(name, val);
		} else if (parent != null && parent.exists(name)) {
			parent.set(name, val);
		} else {
			variables.set(name, val);
		}
	}

	function checkAndSet(name:String, val:Dynamic, interp:Interp):Void {
		if (finals.get(name) == true) {
			throw 'Cannot reassign final variable $name';
		}
		if (types.exists(name)) {
			var newVal = interp.castOrCheckType(val, types.get(name), this);
			variables.set(name, newVal);
		} else if (variables.exists(name)) {
			variables.set(name, val);
		} else if (parent != null && parent.exists(name)) {
			parent.checkAndSet(name, val, interp);
		} else {
			variables.set(name, val);
		}
	}

	function declare(name:String, val:Dynamic, ?type:TypeDecl, ?isFinal:Bool):Void {
		variables.set(name, val);
		if (type != null)
			types.set(name, type);
		else
			types.remove(name);
		if (isFinal == true)
			finals.set(name, true);
		else
			finals.remove(name);
	}
}

typedef ClassMethodInfo = {
	name:String,
	args:Array<FunctionArg>,
	retType:Null<TypeDecl>,
	body:Null<Expr>,
	isStatic:Bool,
	isPublic:Bool,
	?isOverride:Bool,
	?isAbstract:Bool,
	?bytecodeChunk:haxiom.VM.BytecodeChunk,
	?meta:Array<{name:String, params:Array<Dynamic>}>
};

@:allow(haxiom)
class HaxiomClass {
	var name:String;
	var params:Array<TypeParamDef> = [];
	var parentType:TypeDecl;
	var parent:HaxiomClass;
	var isAbstract:Bool = false;
	var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	var methods:Map<String, ClassMethodInfo> = new Map();
	var staticFields:Map<String, Dynamic> = new Map();
	var interfaces:Array<TypeDecl> = [];
	var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	function new(name:String, ?parent:HaxiomClass) {
		this.name = name;
		this.parent = parent;
	}
}

@:allow(haxiom)
class HaxiomInterface {
	var name:String;
	var params:Array<TypeParamDef> = [];
	var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	var methods:Map<String, {
		name:String,
		args:Array<FunctionArg>,
		retType:Null<TypeDecl>,
		?body:Null<Expr>,
		?params:Array<TypeParamDef>,
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	var parents:Array<TypeDecl> = [];
	var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	function new(name:String, ?parents:Array<TypeDecl>) {
		this.name = name;
		this.parents = parents != null ? parents : [];
	}
}

@:allow(haxiom)
class HaxiomInstance {
	var cls:HaxiomClass;
	var fields:Map<String, Dynamic> = new Map();
	var genericBindings:Map<String, TypeDecl> = new Map();

	function new(cls:HaxiomClass) {
		this.cls = cls;
	}
}

@:allow(haxiom)
class HaxiomEnum {
	var name:String;
	var constructors:Map<String, Array<{name:String, type:Null<TypeDecl>}>> = new Map();
	var params:Array<TypeParamDef> = [];

	function new(name:String) {
		this.name = name;
	}
}

@:allow(haxiom)
class HaxiomEnumInstance {
	var enumType:HaxiomEnum;
	var constructorName:String;
	var args:Array<Dynamic>;

	function new(enumType:HaxiomEnum, constructorName:String, args:Array<Dynamic>) {
		this.enumType = enumType;
		this.constructorName = constructorName;
		this.args = args;
	}

	public function toString():String {
		if (args == null || args.length == 0)
			return constructorName;
		return constructorName + "(" + args.join(", ") + ")";
	}
}

@:allow(haxiom)
class HaxiomAbstract {
	var name:String;
	var params:Array<TypeParamDef> = [];
	var underlyingType:TypeDecl;
	var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	var methods:Map<String, ClassMethodInfo> = new Map();
	var staticFields:Map<String, Dynamic> = new Map();
	var meta:Array<{name:String, params:Array<Dynamic>}> = [];
	var fromTypes:Array<String> = [];
	var toTypes:Array<String> = [];

	function new(name:String, underlyingType:TypeDecl) {
		this.name = name;
		this.underlyingType = underlyingType;
	}
}

@:allow(haxiom)
class HaxiomAbstractInstance {
	var abstractType:HaxiomAbstract;
	var underlyingValue:Dynamic;

	function new(abstractType:HaxiomAbstract, underlyingValue:Dynamic) {
		this.abstractType = abstractType;
		this.underlyingValue = underlyingValue;
	}

	public function toString():String {
		return Std.string(underlyingValue);
	}
}

class HaxiomMeta {
	static function cleanName(name:String):String {
		if (name != null && StringTools.startsWith(name, ":")) {
			return name.substring(1);
		}
		return name;
	}

	public static function getType(t:Dynamic):Dynamic {
		if (t == null)
			return null;
		if (Std.isOfType(t, HaxiomClass)) {
			var cls:HaxiomClass = cast t;
			var obj = {};
			if (cls.meta != null) {
				for (m in cls.meta) {
					Reflect.setField(obj, cleanName(m.name), m.params);
				}
			}
			return obj;
		}
		if (Std.isOfType(t, HaxiomInterface)) {
			var itf:HaxiomInterface = cast t;
			var obj = {};
			if (itf.meta != null) {
				for (m in itf.meta) {
					Reflect.setField(obj, cleanName(m.name), m.params);
				}
			}
			return obj;
		}
		if (Std.isOfType(t, HaxiomAbstract)) {
			var abs:HaxiomAbstract = cast t;
			var obj = {};
			if (abs.meta != null) {
				for (m in abs.meta) {
					Reflect.setField(obj, cleanName(m.name), m.params);
				}
			}
			return obj;
		}
		return haxe.rtti.Meta.getType(t);
	}

	public static function getFields(t:Dynamic):Dynamic {
		if (t == null)
			return null;
		if (Std.isOfType(t, HaxiomClass)) {
			var cls:HaxiomClass = cast t;
			var fieldsObj = {};
			var hasAny = false;
			for (fName in cls.fields.keys()) {
				var f = cls.fields.get(fName);
				if (!f.isStatic && f.meta != null && f.meta.length > 0) {
					var fObj = {};
					for (m in f.meta) {
						Reflect.setField(fObj, cleanName(m.name), m.params);
					}
					Reflect.setField(fieldsObj, fName, fObj);
					hasAny = true;
				}
			}
			for (mName in cls.methods.keys()) {
				var m = cls.methods.get(mName);
				if (!m.isStatic && m.meta != null && m.meta.length > 0) {
					var mObj = {};
					for (metaItem in m.meta) {
						Reflect.setField(mObj, cleanName(metaItem.name), metaItem.params);
					}
					Reflect.setField(fieldsObj, mName, mObj);
					hasAny = true;
				}
			}
			return hasAny ? fieldsObj : {};
		}
		if (Std.isOfType(t, HaxiomInterface)) {
			var itf:HaxiomInterface = cast t;
			var fieldsObj = {};
			var hasAny = false;
			for (fName in itf.fields.keys()) {
				var f = itf.fields.get(fName);
				if (f.meta != null && f.meta.length > 0) {
					var fObj = {};
					for (m in f.meta) {
						Reflect.setField(fObj, cleanName(m.name), m.params);
					}
					Reflect.setField(fieldsObj, fName, fObj);
					hasAny = true;
				}
			}
			for (mName in itf.methods.keys()) {
				var m = itf.methods.get(mName);
				if (m.meta != null && m.meta.length > 0) {
					var mObj = {};
					for (metaItem in m.meta) {
						Reflect.setField(mObj, cleanName(metaItem.name), metaItem.params);
					}
					Reflect.setField(fieldsObj, mName, mObj);
					hasAny = true;
				}
			}
			return hasAny ? fieldsObj : {};
		}
		if (Std.isOfType(t, HaxiomAbstract)) {
			var abs:HaxiomAbstract = cast t;
			var fieldsObj = {};
			var hasAny = false;
			for (fName in abs.fields.keys()) {
				var f = abs.fields.get(fName);
				if (!f.isStatic && f.meta != null && f.meta.length > 0) {
					var fObj = {};
					for (m in f.meta) {
						Reflect.setField(fObj, cleanName(m.name), m.params);
					}
					Reflect.setField(fieldsObj, fName, fObj);
					hasAny = true;
				}
			}
			for (mName in abs.methods.keys()) {
				var m = abs.methods.get(mName);
				if (!m.isStatic && m.meta != null && m.meta.length > 0) {
					var mObj = {};
					for (metaItem in m.meta) {
						Reflect.setField(mObj, cleanName(metaItem.name), metaItem.params);
					}
					Reflect.setField(fieldsObj, mName, mObj);
					hasAny = true;
				}
			}
			return hasAny ? fieldsObj : {};
		}
		return haxe.rtti.Meta.getFields(t);
	}

	public static function getStatics(t:Dynamic):Dynamic {
		if (t == null)
			return null;
		if (Std.isOfType(t, HaxiomClass)) {
			var cls:HaxiomClass = cast t;
			var fieldsObj = {};
			var hasAny = false;
			for (fName in cls.fields.keys()) {
				var f = cls.fields.get(fName);
				if (f.isStatic && f.meta != null && f.meta.length > 0) {
					var fObj = {};
					for (m in f.meta) {
						Reflect.setField(fObj, cleanName(m.name), m.params);
					}
					Reflect.setField(fieldsObj, fName, fObj);
					hasAny = true;
				}
			}
			for (mName in cls.methods.keys()) {
				var m = cls.methods.get(mName);
				if (m.isStatic && m.meta != null && m.meta.length > 0) {
					var mObj = {};
					for (metaItem in m.meta) {
						Reflect.setField(mObj, cleanName(metaItem.name), metaItem.params);
					}
					Reflect.setField(fieldsObj, mName, mObj);
					hasAny = true;
				}
			}
			return hasAny ? fieldsObj : {};
		}
		if (Std.isOfType(t, HaxiomAbstract)) {
			var abs:HaxiomAbstract = cast t;
			var fieldsObj = {};
			var hasAny = false;
			for (fName in abs.fields.keys()) {
				var f = abs.fields.get(fName);
				if (f.isStatic && f.meta != null && f.meta.length > 0) {
					var fObj = {};
					for (m in f.meta) {
						Reflect.setField(fObj, cleanName(m.name), m.params);
					}
					Reflect.setField(fieldsObj, fName, fObj);
					hasAny = true;
				}
			}
			for (mName in abs.methods.keys()) {
				var m = abs.methods.get(mName);
				if (m.isStatic && m.meta != null && m.meta.length > 0) {
					var mObj = {};
					for (metaItem in m.meta) {
						Reflect.setField(mObj, cleanName(metaItem.name), metaItem.params);
					}
					Reflect.setField(fieldsObj, mName, mObj);
					hasAny = true;
				}
			}
			return hasAny ? fieldsObj : {};
		}
		return haxe.rtti.Meta.getStatics(t);
	}
}

@:allow(haxiom)
class HaxiomTypedef {
	var name:String;
	var type:TypeDecl;
	var params:Array<TypeParamDef> = [];

	function new(name:String, type:TypeDecl, ?params:Array<TypeParamDef>) {
		this.name = name;
		this.type = type;
		this.params = params != null ? params : [];
	}
}

@:keep
class HaxiomAnchor {
	public static function keep() {
		var s = new haxe.ds.StringMap<Dynamic>();
		var i = new haxe.ds.IntMap<Dynamic>();
		var o = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
		var l = new List<Dynamic>();
	}
}

@:allow(haxiom)
class Interp {
	public static var defaultWhitelist:Array<String> = [
		"Date",
		"DateTools",
		"StringBuf",
		"Xml",
		"haxe.Timer",
		"haxe.Json",
		"haxe.io.Bytes",
		"haxe.io.BytesBuffer",
		"haxe.io.Path",
		"haxe.ds.List",
		"haxe.ds.StringMap",
		"haxe.ds.IntMap",
		"haxe.ds.ObjectMap",
		"StringTools",
		"Lambda",
		"Std",
		"Math",
		"haxe.crypto.Md5",
		"haxe.crypto.Sha1",
		"haxe.crypto.Adler32",
		"haxe.crypto.*",
		"haxe.ds.*",
		"haxe.io.*",
		"haxe.iterators.*",
		"haxe.rtti.*",
		"haxe.xml.*",
		"haxe.Timer",
		"haxe.Constructible",
		"haxe.Exception",
		"haxe.ValueException",
		"haxe.IMap",
		"haxe.DynamicAccess",
		"haxiom.HostRef"
	];

	public var globals:Scope = new Scope();
	public var ffi:FFIRegistry = new FFIRegistry();
	public var externClasses:Map<String, Bool> = new Map();

	var currentThis:Dynamic = null;

	public var currentPackage:Array<String> = [];
	public var moduleResolver:String->String = null;
	public var importWhitelist:Array<String> = defaultWhitelist.copy();
	public var importedModules:Map<String, Scope> = new Map();
	public var functionSignatures:FunctionSignatures = new FunctionSignatures();

	var currentConstructorInstance:Dynamic = null;
	var inAbstractMethod:Bool = false;

	public var activeUsings:Array<Dynamic> = [];

	public var callStack:Array<{method:String, pos:Pos}> = [];
	public var onRuntimeError:Null<ScriptException->Void> = null;
	public var haltedNamespaces:Map<String, Bool> = new Map();

	public function isNamespaceHalted(name:String):Bool {
		if (name == null || name == "")
			return false;
		var segments = name.split(".");
		var rootNamespace = segments[0];
		return haltedNamespaces.exists(rootNamespace);
	}

	public function haltNamespace(name:String):Void {
		if (name == null || name == "" || name == "toplevel" || name == "anonymous")
			return;
		var segments = name.split(".");
		haltedNamespaces.set(segments[0], true);
	}

	public function clearHaltedNamespaces():Void {
		haltedNamespaces.clear();
	}

	var lastEvalPos:Pos = null;

	public var lastSource:Null<String> = null;
	public var preprocessorFlags:Map<String, Bool> = new Map();
	public var lastActiveLocals:Null<Map<String, Dynamic>> = null;
	public var disposed(default, null):Bool = false;

	public function dispose():Void {
		disposed = true;
		globals = new Scope(null); // Clear root scope and references
		importedModules.clear();
		lastActiveLocals = null;
		currentThis = null;
		currentConstructorInstance = null;
		activeUsings = [];
		callStack = [];
	}

	public inline function pushFrame(methodName:String, pos:Pos) {
		callStack.push({method: methodName, pos: pos});
	}

	public inline function popFrame() {
		callStack.pop();
	}

	function evaluateMetadata(metaList:Array<{name:String, params:Array<Expr>}>, scope:Scope):Array<{name:String, params:Array<Dynamic>}> {
		if (metaList == null)
			return [];
		return [
			for (m in metaList) {
				var isOp = (m.name == ":op" || m.name == "op");
				{
					name: m.name,
					params: [
						for (p in m.params) {
							if (isOp) {
								p;
							} else {
								try {
									eval(p, scope);
								} catch (e:Dynamic) {
									p;
								}
							}
						}
					]
				}
			}
		];
	}

	function initDefaultFlags() {
		#if eval preprocessorFlags.set("eval", true); #end
		#if js preprocessorFlags.set("js", true); #end
		#if sys preprocessorFlags.set("sys", true); #end
		#if cpp preprocessorFlags.set("cpp", true); #end
		#if hl preprocessorFlags.set("hl", true); #end
		#if neko preprocessorFlags.set("neko", true); #end
		#if flash preprocessorFlags.set("flash", true); #end
		#if java preprocessorFlags.set("java", true); #end
		#if cs preprocessorFlags.set("cs", true); #end
		#if mac preprocessorFlags.set("mac", true);
		preprocessorFlags.set("macos", true); #end
		#if windows preprocessorFlags.set("windows", true); #end
		#if linux preprocessorFlags.set("linux", true); #end
		#if debug preprocessorFlags.set("debug", true); #end
		preprocessorFlags.set("haxiom", true);
		preprocessorFlags.set("haxiom_script", true);
	}

	public function new() {
		initDefaultFlags();
		// Core standard print/trace redirection with PosInfos
		globals.declare("trace", Reflect.makeVarArgs((args:Array<Dynamic>) -> {
			var str = [for (a in args) Std.string(a)].join(", ");
			var fileStr = lastEvalPos != null && lastEvalPos.file != null ? lastEvalPos.file : "script";
			var lineVal = lastEvalPos != null ? lastEvalPos.line : 1;
			var clsName = currentThis != null && Std.isOfType(currentThis, HaxiomClass) ? (cast currentThis : HaxiomClass).name : "script";
			var mName = callStack.length > 0 ? callStack[callStack.length - 1].method : "toplevel";
			var posInfos:haxe.PosInfos = {
				fileName: fileStr,
				lineNumber: lineVal,
				className: clsName,
				methodName: mName
			};
			haxe.Log.trace(str, posInfos);
		}));

		// Dynamic Math binding
		globals.declare("Math", Math);

		// Expose global Std object
		var mapPlaceholder = {__isMapPlaceholder: true};
		var stdObj = {
			string: Std.string,
			parseInt: Std.parseInt,
			parseFloat: Std.parseFloat,
			int: Std.int,
			random: Std.random,
			isOfType: (v:Dynamic, t:Dynamic) -> {
				if (t == mapPlaceholder) {
					return Std.isOfType(v, haxe.Constraints.IMap);
				}
				if (Std.isOfType(t, HaxiomClass)) {
					if (v == null || !Std.isOfType(v, HaxiomInstance))
						return false;
					var inst:HaxiomInstance = cast v;
					var curr = inst.cls;
					while (curr != null) {
						if (curr == t)
							return true;
						curr = curr.parent;
					}
					return false;
				}
				if (Std.isOfType(t, HaxiomInterface)) {
					if (v == null || !Std.isOfType(v, HaxiomInstance))
						return false;
					var inst:HaxiomInstance = cast v;
					var itf:HaxiomInterface = cast t;
					var curr = inst.cls;
					while (curr != null) {
						for (itfDecl in curr.interfaces) {
							switch (itfDecl) {
								case TPath(itfPath, _):
									var itfName = itfPath.join(".");
									if (isInterfaceCompatible(itfName, itf.name, globals)) return true;
								default:
							}
						}
						curr = curr.parent;
					}
					return false;
				}
				if (Std.isOfType(t, HaxiomAbstract)) {
					if (v == null || !Std.isOfType(v, HaxiomAbstractInstance))
						return false;
					var inst:HaxiomAbstractInstance = cast v;
					return inst.abstractType == t;
				}
				return Std.isOfType(v, t);
			}
		};
		globals.declare("Std", stdObj);
		globals.declare("String", String);
		globals.declare("Array", Array);
		globals.declare("List", haxe.ds.List);
		globals.declare("Map", mapPlaceholder);
		globals.declare("StringTools", StringTools);
		globals.declare("Date", Date);
		globals.declare("Xml", Xml);

		var lambdaObj = {
			array: (it:Dynamic) -> Lambda.array(it),
			list: (it:Dynamic) -> Lambda.list(it),
			count: (it:Dynamic, ?pred:Dynamic) -> {
				if (pred == null)
					return Lambda.count(it);
				return Lambda.count(it, (x) -> Reflect.callMethod(null, pred, [x]));
			},
			empty: (it:Dynamic) -> Lambda.empty(it),
			indexOf: (it:Dynamic, val:Dynamic) -> Lambda.indexOf(it, val),
			find: (it:Dynamic, f:Dynamic) -> {
				return Lambda.find(it, (x) -> Reflect.callMethod(null, f, [x]));
			},
			exists: (it:Dynamic, f:Dynamic) -> {
				return Lambda.exists(it, (x) -> Reflect.callMethod(null, f, [x]));
			},
			foreach: (it:Dynamic, f:Dynamic) -> {
				return Lambda.foreach(it, (x) -> Reflect.callMethod(null, f, [x]));
			},
			iter: (it:Dynamic, f:Dynamic) -> {
				Lambda.iter(it, (x) -> Reflect.callMethod(null, f, [x]));
				return null;
			},
			map: (it:Dynamic, f:Dynamic) -> {
				return Lambda.map(it, (x) -> Reflect.callMethod(null, f, [x]));
			},
			filter: (it:Dynamic, f:Dynamic) -> {
				return Lambda.filter(it, (x) -> Reflect.callMethod(null, f, [x]));
			},
			fold: (it:Dynamic, f:Dynamic, first:Dynamic) -> {
				return Lambda.fold(it, (x, acc) -> Reflect.callMethod(null, f, [x, acc]), first);
			},
			has: (it:Dynamic, el:Dynamic) -> Lambda.has(it, el)
		};
		globals.declare("Lambda", lambdaObj);

		// Ensure DCE keep
		HaxiomAnchor.keep();
	}

	public var useVM:Bool = false;
	public var debugMode:Bool = true;
	public var maxInstructions:Int = 0;
	public var instructionsCount:Int = 0;
	public var maxMemory:Int = 0;
	public var memoryUsage:Int = 0;

	public function trackMemory(amount:Int, ?pos:Pos, ?callStackForEx:Array<{method:String, pos:Pos}>):Void {
		if (maxMemory <= 0)
			return;
		memoryUsage += amount;
		if (memoryUsage > maxMemory) {
			var actualPos = pos != null ? pos : (lastEvalPos != null ? lastEvalPos : {line: 1, col: 1, file: "script"});
			var fileInfo = actualPos.file != null ? actualPos.file : "script";
			var lineVal = actualPos.line;
			var colVal = actualPos.col;
			var locationStr = 'Runtime Error: Memory limit exceeded ($maxMemory units) at ' + fileInfo + ':' + lineVal + ':' + colVal;
			var stack = callStackForEx != null ? callStackForEx : callStack.copy();
			throw new haxiom.ScriptException("Memory limit exceeded", stack, locationStr, lineVal, colVal, fileInfo);
		}
	}

	public function trackNewAllocation(val:Dynamic, ?pos:Pos, ?callStackForEx:Array<{method:String, pos:Pos}>):Void {
		if (maxMemory <= 0 || val == null)
			return;
		if (Std.isOfType(val, Array)) {
			var arr:Array<Dynamic> = cast val;
			trackMemory(arr.length > 0 ? arr.length : 1, pos, callStackForEx);
		} else if (Std.isOfType(val, haxe.Constraints.IMap)) {
			var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast val;
			var count = 0;
			for (k in map.keys())
				count++;
			trackMemory(count > 0 ? count : 1, pos, callStackForEx);
		} else if (Std.isOfType(val, HaxiomInstance)) {
			var inst:HaxiomInstance = cast val;
			var numFields = 0;
			for (k in inst.fields.keys())
				numFields++;
			trackMemory(numFields > 0 ? numFields : 1, pos, callStackForEx);
		} else if (Type.typeof(val) == TObject) {
			var numFields = Reflect.fields(val).length;
			trackMemory(numFields > 0 ? numFields : 1, pos, callStackForEx);
		} else {
			var cls = Type.getClass(val);
			if (cls != null) {
				var clsName = safeGetClassName(cls);
				if (clsName == "haxe.ds.List" || clsName == "List") {
					var list:List<Dynamic> = cast val;
					trackMemory(list.length > 0 ? list.length : 1, pos, callStackForEx);
				} else if (clsName == "haxe.ds.Vector" || clsName == "eval.Vector") {
					var vec:haxe.ds.Vector<Dynamic> = cast val;
					trackMemory(vec.length > 0 ? vec.length : 1, pos, callStackForEx);
				}
			}
		}
	}

	public function evalNew(typeDecl:TypeDecl, argsExprs:Array<Expr>, scope:Scope, pos:Pos):Dynamic {
		var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
		switch (typeDecl) {
			case TPath(path, params):
				var fqName = path.join(".");
				var callee:Dynamic = resolveTypePath(path, scope);

				// 1. Check Generic Mapping Lookup
				if (params.length > 0) {
					var paramNames = [];
					for (p in params) {
						switch (p) {
							case TPath(pPath, _):
								var resolvedParam = resolveTypePath(pPath, scope);
								if (resolvedParam != null) {
									if (Std.isOfType(resolvedParam, Class)) {
										var className = safeGetClassName(resolvedParam);
										if (className != null) {
											paramNames.push(className);
										} else {
											paramNames.push(pPath.join("."));
										}
									} else if (Std.isOfType(resolvedParam, HaxiomClass)) {
										paramNames.push((cast resolvedParam : HaxiomClass).name);
									} else {
										paramNames.push(pPath.join("."));
									}
								} else {
									paramNames.push(pPath.join("."));
								}
							default:
								paramNames.push("Dynamic");
						}
					}
					var genericSig = fqName + "<" + paramNames.join(",") + ">";
					var mappedGenClass = this.ffi.exposedGenerics.get(genericSig);
					if (mappedGenClass != null) {
						var cls = resolveNativeClass(mappedGenClass);
						if (cls != null)
							callee = cls;
					}
				}

				// 2. Check Multi-type Map Factory
				if (fqName == "Map" || fqName == "haxe.ds.Map") {
					if (params.length > 0) {
						switch (params[0]) {
							case TPath(pPath, _):
								var keyName = pPath[pPath.length - 1];
								if (keyName == "String") {
									return new haxe.ds.StringMap<Dynamic>();
								} else if (keyName == "Int") {
									return new haxe.ds.IntMap<Dynamic>();
								} else if (keyName == "Dynamic") {
									return new haxiom.DynamicMap();
								} else {
									return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
								}
							default:
						}
					}
					return new haxiom.DynamicMap();
				}

				if (fqName == "Vector" || fqName == "haxe.ds.Vector") {
					return new haxe.ds.Vector(args[0]);
				}

				// 3. Check Exposed Abstracts constructor redirection
				var absInfo = this.ffi.exposedAbstracts.get(fqName);
				if (absInfo != null) {
					var implCls = resolveAbstractImpl(fqName, absInfo.implClass);
					if (implCls != null) {
						var newMethod = Reflect.field(implCls, "_new");
						if (newMethod != null) {
							return Reflect.callMethod(null, newMethod, args);
						}
					}
				}

				// 4. Instantiate Class (Haxiom or Native)
				if (callee == null) {
					throw 'Class not found: $fqName';
				}

				if (Std.isOfType(callee, HaxiomClass)) {
					var cls:HaxiomClass = cast callee;
					if (cls.isAbstract) {
						throw new haxiom.CompileException('Cannot instantiate abstract class ${cls.name}', 0, 0, cls.name);
					}
					var inst = new HaxiomInstance(cls);
					populateGenericBindings(inst, cls, params, null, null, scope);

					var curr = cls;
					while (curr != null) {
						for (f in curr.fields) {
							if (!f.isStatic) {
								inst.fields.set(f.name, f.expr != null ? eval(f.expr, scope) : null);
							}
						}
						curr = curr.parent;
					}

					var constr = findMethod(cls, "new");
					if (constr != null) {
						checkMemberAccess(cls, constr.isPublic, pos, "new");
						var cScope = Scope.create(scope);
						cScope.declare("this", inst);
						for (i in 0...constr.args.length) {
							var arg = constr.args[i];
							var val = i < args.length ? args[i] : null;
							val = castOrCheckType(val, arg.type, cScope);
							cScope.declare(arg.name, val, arg.type);
						}
						var oldThis = currentThis;
						currentThis = inst;
						var oldConstrInst = currentConstructorInstance;
						currentConstructorInstance = inst;
						pushFrame(cls.name + ".new", constr.body != null ? constr.body.pos : {line: 1, col: 1});
						try {
							if (useVM || (constr.body == null && (constr : Dynamic).bytecodeChunk != null)) {
								var cDyn:Dynamic = constr;
								if (cDyn.bytecodeChunk == null && constr.body != null) {
									cDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(constr.body, constr.args, false, false, debugMode, "new");
								}
								haxiom.VM.runChunk(this, cDyn.bytecodeChunk, cScope, inst, cls.name + ".new", args);
							} else {
								eval(constr.body, cScope);
							}
							popFrame();
							Scope.recycle(cScope);
						} catch (e:ControlFlow) {
							popFrame();
							Scope.recycle(cScope);
							switch (e) {
								case Return(_):
								default: throw e;
							}
						} catch (err:Dynamic) {
							popFrame();
							Scope.recycle(cScope);
							throw err;
						}
						currentConstructorInstance = oldConstrInst;
						currentThis = oldThis;
					}
					return inst;
				}

				if (Std.isOfType(callee, HaxiomAbstract)) {
					var abs:HaxiomAbstract = cast callee;
					var inst = new HaxiomAbstractInstance(abs, null);
					var constr = abs.methods.get("new");
					if (constr != null) {
						var cScope = Scope.create(scope);
						cScope.declare("this", inst);
						for (i in 0...constr.args.length) {
							var arg = constr.args[i];
							var val = i < args.length ? args[i] : null;
							val = castOrCheckType(val, arg.type, cScope);
							cScope.declare(arg.name, val, arg.type);
						}
						var oldThis = currentThis;
						currentThis = inst;
						var oldAbstract = inAbstractMethod;
						inAbstractMethod = true;
						pushFrame(abs.name + ".new", constr.body != null ? constr.body.pos : {line: 1, col: 1});
						try {
							if (useVM || (constr.body == null && (constr : Dynamic).bytecodeChunk != null)) {
								var cDyn:Dynamic = constr;
								if (cDyn.bytecodeChunk == null && constr.body != null) {
									cDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(constr.body, constr.args, false, false, debugMode, "new");
								}
								haxiom.VM.runChunk(this, cDyn.bytecodeChunk, cScope, inst, abs.name + ".new", args);
							} else {
								eval(constr.body, cScope);
							}
							popFrame();
							Scope.recycle(cScope);
						} catch (e:ControlFlow) {
							popFrame();
							Scope.recycle(cScope);
							switch (e) {
								case Return(_):
								default: throw e;
							}
						} catch (err:Dynamic) {
							popFrame();
							Scope.recycle(cScope);
							throw err;
						}
						inAbstractMethod = oldAbstract;
						currentThis = oldThis;
					}
					return inst;
				}

				var calleeClassName = safeGetClassName(callee);
				if (calleeClassName != null) {
					switch (calleeClassName) {
						case "haxe.ds.StringMap":
							return new haxe.ds.StringMap<Dynamic>();
						case "haxe.ds.IntMap":
							return new haxe.ds.IntMap<Dynamic>();
						case "haxe.ds.ObjectMap":
							return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
						default:
							#if haxiom_debug
							trace('Type.createInstance: ' + calleeClassName + ' with args: ' + args);
							#end
							return Type.createInstance(cast callee, args);
					}
				}

				throw 'Cannot instantiate type: $fqName';
			default:
				throw "Constructor call expects a type path";
		}
	}

	public function execute(expr:Expr):Dynamic {
		instructionsCount = 0;
		memoryUsage = 0;
		currentPackage = [];
		callStack = [];
		activeUsings = [];
		lastActiveLocals = null;
		lastEvalPos = expr.pos;
		try {
			if (useVM) {
				var chunk = BytecodeCompiler.compile(expr, null, true, false, debugMode);
				return VM.runChunk(this, chunk, globals, null, "toplevel");
			}
			return eval(expr, globals);
		} catch (e:ControlFlow) {
			switch (e) {
				case Return(val):
					return val;
				default:
					throw "Unexpected control flow break/continue at top-level";
			}
		} catch (e:Dynamic) {
			var traceLines = [];
			var isScriptException = Std.isOfType(e, haxiom.ScriptException);

			var formatted = "";
			var finalException:Dynamic = null;
			if (isScriptException) {
				finalException = e;
			} else {
				var errPos = lastEvalPos != null ? lastEvalPos : expr.pos;
				var fileInfo = errPos.file != null ? errPos.file : "script";
				var lineVal = errPos != null ? errPos.line : 1;
				var colVal = errPos != null ? errPos.col : 1;

				var codeFrame = ScriptException.makeCodeFrame(lastSource, lineVal, colVal, fileInfo);
				var locationStr = 'Runtime Error: ' + Std.string(e) + ' at ' + fileInfo + ':' + lineVal + ':' + colVal;
				if (codeFrame != "") {
					locationStr += "\n" + codeFrame;
				}
				traceLines.push(locationStr);
				var i = callStack.length - 1;
				while (i >= 0) {
					var frame = callStack[i];
					var fileInfoFrame = frame.pos.file != null ? frame.pos.file : "script";
					var framePos = (i == callStack.length - 1 && lastEvalPos != null) ? lastEvalPos : frame.pos;
					traceLines.push('    at ' + frame.method + ' (' + fileInfoFrame + ':' + framePos.line + ':' + framePos.col + ')');
					i--;
				}
				if (callStack.length == 0) {
					traceLines.push('    at toplevel (' + fileInfo + ':' + lineVal + ':' + colVal + ')');
				}
				formatted = traceLines.join("\n");
				finalException = new haxiom.ScriptException(e, callStack.copy(), formatted, lineVal, colVal, fileInfo);
			}

			if (onRuntimeError != null) {
				onRuntimeError(finalException);
				return null;
			}
			throw finalException;
		}
	}

	public function executeChunk(chunk:haxiom.VM.BytecodeChunk):Dynamic {
		instructionsCount = 0;
		memoryUsage = 0;
		currentPackage = [];
		callStack = [];
		activeUsings = [];
		lastActiveLocals = null;
		if (chunk.positions.length > 0 && chunk.positions[0] != null) {
			lastEvalPos = chunk.positions[0];
		}
		try {
			return VM.runChunk(this, chunk, globals, null, "toplevel");
		} catch (e:ControlFlow) {
			switch (e) {
				case Return(val):
					return val;
				default:
					throw "Unexpected control flow break/continue at top-level";
			}
		} catch (e:Dynamic) {
			trace("DEBUG ORIGINAL CALL STACK: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			var traceLines = [];
			var isScriptException = Std.isOfType(e, haxiom.ScriptException);

			var formatted = "";
			var finalException:Dynamic = null;
			if (isScriptException) {
				finalException = e;
			} else {
				var errPos = lastEvalPos != null ? lastEvalPos : {line: 1, col: 1};
				var fileInfo = errPos.file != null ? errPos.file : "script";
				var lineVal = errPos != null ? errPos.line : 1;
				var colVal = errPos != null ? errPos.col : 1;

				var codeFrame = ScriptException.makeCodeFrame(lastSource, lineVal, colVal, fileInfo);
				var locationStr = 'Runtime Error: ' + Std.string(e) + ' at ' + fileInfo + ':' + lineVal + ':' + colVal;
				if (codeFrame != "") {
					locationStr += "\n" + codeFrame;
				}
				traceLines.push(locationStr);
				var i = callStack.length - 1;
				while (i >= 0) {
					var frame = callStack[i];
					var fileInfoFrame = frame.pos.file != null ? frame.pos.file : "script";
					var framePos = (i == callStack.length - 1 && lastEvalPos != null) ? lastEvalPos : frame.pos;
					traceLines.push('    at ' + frame.method + ' (' + fileInfoFrame + ':' + framePos.line + ':' + framePos.col + ')');
					i--;
				}
				if (callStack.length == 0) {
					traceLines.push('    at toplevel (' + fileInfo + ':' + lineVal + ':' + colVal + ')');
				}
				formatted = traceLines.join("\n");
				finalException = new haxiom.ScriptException(e, callStack.copy(), formatted, lineVal, colVal, fileInfo, lastActiveLocals);
				lastActiveLocals = null;
			}

			if (onRuntimeError != null) {
				onRuntimeError(finalException);
				return null;
			}
			throw finalException;
		}
	}

	function getTypeName(v:Dynamic):String {
		if (v == null)
			return "null";
		if (Std.isOfType(v, Int))
			return "Int";
		if (Std.isOfType(v, Float))
			return "Float";
		if (Std.isOfType(v, String))
			return "String";
		if (Std.isOfType(v, Bool))
			return "Bool";
		if (Std.isOfType(v, Array))
			return "Array";
		if (Reflect.isFunction(v))
			return "function";
		var cls = Type.getClass(v);
		if (cls != null) {
			var name = safeGetClassName(cls);
			if (name != null)
				return name;
		}
		return "Unknown";
	}

	inline function checkArgCount(args:Array<Dynamic>, expectedMin:Int, expectedMax:Int, methodName:String):Void {
		if (args.length < expectedMin || args.length > expectedMax) {
			throw 'Method $methodName expected between $expectedMin and $expectedMax arguments but got ${args.length}';
		}
	}

	inline function checkNum(v:Dynamic, methodName:String, argName:String = "argument"):Void {
		if (!Std.isOfType(v, Float) && !Std.isOfType(v, Int)) {
			throw '$methodName expected a number for $argName but got ${getTypeName(v)}';
		}
	}

	inline function checkString(v:Dynamic, methodName:String, argName:String = "argument"):Void {
		if (!Std.isOfType(v, String)) {
			throw '$methodName expected a String for $argName but got ${getTypeName(v)}';
		}
	}

	inline function checkInt(v:Dynamic, methodName:String, argName:String = "argument"):Void {
		if (!Std.isOfType(v, Int)) {
			throw '$methodName expected an Int for $argName but got ${getTypeName(v)}';
		}
	}

	inline function checkFunction(v:Dynamic, methodName:String, argName:String = "callback"):Void {
		if (v == null || !Reflect.isFunction(v)) {
			throw '$methodName expected a function for $argName but got ${getTypeName(v)}';
		}
	}

	public var fieldAccessFilter:Null<(target:Dynamic, field:String) -> Bool> = null;

	public function evalField(obj:Dynamic, field:String, scope:Scope, pos:Pos):Dynamic {
		if (obj == null)
			throw 'Cannot read field "$field" of null';

		if (fieldAccessFilter != null && !fieldAccessFilter(obj, field)) {
			var pStr = pos != null ? '${pos.file != null ? pos.file : "script"}:${pos.line}:${pos.col}' : "script";
			throw 'Security Error: Access to field "$field" is forbidden at ${pStr}';
		}

		if (importWhitelist != null) {
			var name = getClassNameOf(obj);
			if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
				throwSecurityErrorForUnwhitelistedClass(field, name);
			}
		}

		if (obj == haxe.Json && field == "stringify") {
			return (cast function(value:Dynamic, ?replacer:Dynamic, ?space:String):String {
				checkSafeToSerialize(value);
				return haxe.Json.stringify(value, replacer, space);
			} : Dynamic);
		}
		if (obj == haxe.Serializer && field == "run") {
			return (cast function(v:Dynamic) {
				checkSafeToSerialize(v);
				return haxe.Serializer.run(v);
			} : Dynamic);
		}
		if (Std.isOfType(obj, haxe.Serializer) && field == "serialize") {
			return (cast function(v:Dynamic) {
				checkSafeToSerialize(v);
				var serializer:haxe.Serializer = cast obj;
				serializer.serialize(v);
			} : Dynamic);
		}

		if (Reflect.isFunction(obj) && field == "bind") {
			return Reflect.makeVarArgs(function(boundArgs:Array<Dynamic>) {
				return Reflect.makeVarArgs(function(remainingArgs:Array<Dynamic>) {
					return Reflect.callMethod(null, obj, boundArgs.concat(remainingArgs));
				});
			});
		}

		if (Std.isOfType(obj, String)) {
			var str:String = cast obj;
			if (field == "length")
				return str.length;
			switch (field) {
				case "split":
					return (delim:Dynamic) -> {
						checkString(delim, "String.split", "delimiter");
						return str.split(delim);
					};
				case "indexOf":
					return (sub:Dynamic, ?start:Dynamic) -> {
						checkString(sub, "String.indexOf", "substring");
						if (start != null)
							checkInt(start, "String.indexOf", "start index");
						return str.indexOf(sub, start);
					};
				case "lastIndexOf":
					return (sub:Dynamic, ?start:Dynamic) -> {
						checkString(sub, "String.lastIndexOf", "substring");
						if (start != null)
							checkInt(start, "String.lastIndexOf", "start index");
						return str.lastIndexOf(sub, start);
					};
				case "charAt":
					return (idx:Dynamic) -> {
						checkInt(idx, "String.charAt", "index");
						return str.charAt(idx);
					};
				case "charCodeAt":
					return (idx:Dynamic) -> {
						checkInt(idx, "String.charCodeAt", "index");
						return str.charCodeAt(idx);
					};
				case "substring":
					return (start:Dynamic, ?end:Dynamic) -> {
						checkInt(start, "String.substring", "start index");
						if (end != null)
							checkInt(end, "String.substring", "end index");
						return str.substring(start, end);
					};
				case "substr":
					return (start:Dynamic, ?len:Dynamic) -> {
						checkInt(start, "String.substr", "start index");
						if (len != null)
							checkInt(len, "String.substr", "length");
						return str.substr(start, len);
					};
				case "toLowerCase":
					return () -> str.toLowerCase();
				case "toUpperCase":
					return () -> str.toUpperCase();
				case "toString":
					return () -> str;
				case "startsWith":
					return (start:Dynamic) -> {
						checkString(start, "StringTools.startsWith", "prefix");
						return StringTools.startsWith(str, start);
					};
				case "endsWith":
					return (end:Dynamic) -> {
						checkString(end, "StringTools.endsWith", "suffix");
						return StringTools.endsWith(str, end);
					};
				case "trim":
					return () -> StringTools.trim(str);
				case "ltrim":
					return () -> StringTools.ltrim(str);
				case "rtrim":
					return () -> StringTools.rtrim(str);
				case "replace":
					return (sub:Dynamic, by:Dynamic) -> {
						checkString(sub, "StringTools.replace", "sub");
						checkString(by, "StringTools.replace", "by");
						return StringTools.replace(str, sub, by);
					};
				case "lpad":
					return (c:Dynamic, l:Dynamic) -> {
						checkString(c, "StringTools.lpad", "char");
						checkInt(l, "StringTools.lpad", "length");
						return StringTools.lpad(str, c, l);
					};
				case "rpad":
					return (c:Dynamic, l:Dynamic) -> {
						checkString(c, "StringTools.rpad", "char");
						checkInt(l, "StringTools.rpad", "length");
						return StringTools.rpad(str, c, l);
					};
				case "urlEncode":
					return () -> StringTools.urlEncode(str);
				case "urlDecode":
					return () -> StringTools.urlDecode(str);
				case "htmlEscape":
					return (?quotes:Dynamic) -> {
						if (quotes != null && !Std.isOfType(quotes, Bool))
							throw "String.htmlEscape expected a Bool for quotes";
						return StringTools.htmlEscape(str, quotes);
					};
				case "htmlUnescape":
					return () -> StringTools.htmlUnescape(str);
				default:
			}
		}
		if (Std.isOfType(obj, haxe.io.Bytes)) {
			var b:haxe.io.Bytes = cast obj;
			if (field == "length")
				return b.length;
			switch (field) {
				case "get":
					return (pos:Int) -> b.get(pos);
				case "set":
					return (pos:Int, v:Int) -> b.set(pos, v);
				case "getString":
					return (pos:Int, len:Int) -> b.getString(pos, len);
				case "toHex":
					return () -> b.toHex();
				case "toString":
					return () -> b.toString();
				case "sub":
					return (pos:Int, len:Int) -> b.sub(pos, len);
				default:
			}
		}

		if (Std.isOfType(obj, Array)) {
			var arr:Array<Dynamic> = cast obj;
			if (field == "length")
				return arr.length;
			switch (field) {
				case "concat":
					return (other:Dynamic) -> {
						if (!Std.isOfType(other, Array))
							throw "Array.concat expected an Array for argument but got " + getTypeName(other);
						var newArr = arr.concat(other);
						trackNewAllocation(newArr);
						return newArr;
					};
				case "push":
					return (x:Dynamic) -> {
						trackMemory(1);
						return arr.push(x);
					};
				case "pop":
					return () -> arr.pop();
				case "shift":
					return () -> arr.shift();
				case "unshift":
					return (x:Dynamic) -> {
						trackMemory(1);
						arr.unshift(x);
						return null;
					};
				case "remove":
					return (x:Dynamic) -> arr.remove(x);
				case "indexOf":
					return (x:Dynamic, ?start:Dynamic) -> {
						if (start != null)
							checkInt(start, "Array.indexOf", "start index");
						return arr.indexOf(x, start);
					};
				case "lastIndexOf":
					return (x:Dynamic, ?start:Dynamic) -> {
						if (start != null)
							checkInt(start, "Array.lastIndexOf", "start index");
						return arr.lastIndexOf(x, start);
					};
				case "insert":
					return (idx:Dynamic, x:Dynamic) -> {
						checkInt(idx, "Array.insert", "index");
						trackMemory(1);
						arr.insert(idx, x);
						return null;
					};
				case "reverse":
					return () -> {
						arr.reverse();
						return null;
					};
				case "sort":
					return (f:Dynamic) -> {
						checkFunction(f, "Array.sort", "comparator");
						arr.sort((a, b) -> Reflect.callMethod(null, f, [a, b]));
						return null;
					};
				case "resize":
					return (len:Dynamic) -> {
						checkInt(len, "Array.resize", "length");
						var newLen:Int = len;
						if (newLen > arr.length) {
							trackMemory(newLen - arr.length);
						}
						arr.resize(newLen);
						return null;
					};
				case "contains":
					return (x:Dynamic) -> arr.contains(x);
				case "join":
					return (sep:Dynamic) -> {
						checkString(sep, "Array.join", "separator");
						return arr.join(sep);
					};
				case "slice":
					return (start:Dynamic, ?end:Dynamic) -> {
						checkInt(start, "Array.slice", "start index");
						if (end != null)
							checkInt(end, "Array.slice", "end index");
						var res = arr.slice(start, end);
						trackNewAllocation(res);
						return res;
					};
				case "copy":
					return () -> {
						var res = arr.copy();
						trackNewAllocation(res);
						return res;
					};
				case "filter":
					return (f:Dynamic) -> {
						checkFunction(f, "Array.filter", "callback");
						var res = arr.filter((x) -> Reflect.callMethod(null, f, [x]));
						trackNewAllocation(res);
						return res;
					};
				case "map":
					return (f:Dynamic) -> {
						checkFunction(f, "Array.map", "callback");
						var res = arr.map((x) -> Reflect.callMethod(null, f, [x]));
						trackNewAllocation(res);
						return res;
					};
				case "toString":
					return () -> arr.toString();
				case "iterator":
					return () -> arr.iterator();
				case "keyValueIterator":
					return () -> arr.keyValueIterator();
				default:
			}
		}
		if (Std.isOfType(obj, haxe.ds.List)) {
			var list:haxe.ds.List<Dynamic> = cast obj;
			switch (field) {
				case "add":
					return (item:Dynamic) -> {
						trackMemory(1);
						list.add(item);
						return null;
					};
				case "push":
					return (item:Dynamic) -> {
						trackMemory(1);
						list.push(item);
						return null;
					};
				case "first":
					return () -> list.first();
				case "last":
					return () -> list.last();
				case "pop":
					return () -> list.pop();
				case "isEmpty":
					return () -> list.isEmpty();
				case "clear":
					return () -> {
						list.clear();
						return null;
					};
				case "remove":
					return (item:Dynamic) -> list.remove(item);
				case "iterator":
					return () -> list.iterator();
				case "toString":
					return () -> list.toString();
				case "join":
					return (sep:Dynamic) -> {
						checkString(sep, "List.join", "separator");
						return list.join(sep);
					};
				case "filter":
					return (f:Dynamic) -> {
						checkFunction(f, "List.filter", "callback");
						var res = list.filter((x) -> Reflect.callMethod(null, f, [x]));
						trackNewAllocation(res);
						return res;
					};
				case "map":
					return (f:Dynamic) -> {
						checkFunction(f, "List.map", "callback");
						var res = list.map((x) -> Reflect.callMethod(null, f, [x]));
						trackNewAllocation(res);
						return res;
					};
				default:
			}
		}
		if (obj == String) {
			switch (field) {
				case "fromCharCode":
					return (code:Dynamic) -> {
						checkInt(code, "String.fromCharCode", "code");
						return String.fromCharCode(code);
					};
				default:
			}
		}
		if (obj == StringTools) {
			switch (field) {
				case "urlEncode":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.urlEncode", "s");
						return StringTools.urlEncode(s);
					};
				case "urlDecode":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.urlDecode", "s");
						return StringTools.urlDecode(s);
					};
				case "htmlEscape":
					return (s:Dynamic, ?quotes:Dynamic) -> {
						checkString(s, "StringTools.htmlEscape", "s");
						if (quotes != null && !Std.isOfType(quotes, Bool))
							throw "StringTools.htmlEscape expected a Bool for quotes";
						return StringTools.htmlEscape(s, quotes);
					};
				case "htmlUnescape":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.htmlUnescape", "s");
						return StringTools.htmlUnescape(s);
					};
				case "hex":
					return (n:Dynamic, ?digits:Dynamic) -> {
						checkInt(n, "StringTools.hex", "n");
						if (digits != null)
							checkInt(digits, "StringTools.hex", "digits");
						return StringTools.hex(n, digits);
					};
				case "fastCodeAt":
					return (s:Dynamic, index:Dynamic) -> {
						checkString(s, "StringTools.fastCodeAt", "s");
						checkInt(index, "StringTools.fastCodeAt", "index");
						return StringTools.fastCodeAt(s, index);
					};
				case "isSpace":
					return (s:Dynamic, index:Dynamic) -> {
						checkString(s, "StringTools.isSpace", "s");
						checkInt(index, "StringTools.isSpace", "index");
						return StringTools.isSpace(s, index);
					};
				case "trim":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.trim", "s");
						return StringTools.trim(s);
					};
				case "ltrim":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.ltrim", "s");
						return StringTools.ltrim(s);
					};
				case "rtrim":
					return (s:Dynamic) -> {
						checkString(s, "StringTools.rtrim", "s");
						return StringTools.rtrim(s);
					};
				case "replace":
					return (s:Dynamic, sub:Dynamic, by:Dynamic) -> {
						checkString(s, "StringTools.replace", "s");
						checkString(sub, "StringTools.replace", "sub");
						checkString(by, "StringTools.replace", "by");
						return StringTools.replace(s, sub, by);
					};
				case "startsWith":
					return (s:Dynamic, prefix:Dynamic) -> {
						checkString(s, "StringTools.startsWith", "s");
						checkString(prefix, "StringTools.startsWith", "prefix");
						return StringTools.startsWith(s, prefix);
					};
				case "endsWith":
					return (s:Dynamic, suffix:Dynamic) -> {
						checkString(s, "StringTools.endsWith", "s");
						checkString(suffix, "StringTools.endsWith", "suffix");
						return StringTools.endsWith(s, suffix);
					};
				case "lpad":
					return (s:Dynamic, c:Dynamic, l:Dynamic) -> {
						checkString(s, "StringTools.lpad", "s");
						checkString(c, "StringTools.lpad", "char");
						checkInt(l, "StringTools.lpad", "length");
						return StringTools.lpad(s, c, l);
					};
				case "rpad":
					return (s:Dynamic, c:Dynamic, l:Dynamic) -> {
						checkString(s, "StringTools.rpad", "s");
						checkString(c, "StringTools.rpad", "char");
						checkInt(l, "StringTools.rpad", "length");
						return StringTools.rpad(s, c, l);
					};
				default:
			}
		}
		if (obj == Date) {
			switch (field) {
				case "now":
					return () -> Date.now();
				case "fromTime":
					return (t:Dynamic) -> {
						checkNum(t, "Date.fromTime");
						return Date.fromTime(t);
					};
				case "fromString":
					return (s:Dynamic) -> {
						checkString(s, "Date.fromString", "s");
						return Date.fromString(s);
					};
				default:
			}
		}
		if (obj == Math) {
			if (field == "PI")
				return Math.PI;
			if (field == "NaN")
				return Math.NaN;
			if (field == "NEGATIVE_INFINITY")
				return Math.NEGATIVE_INFINITY;
			if (field == "POSITIVE_INFINITY")
				return Math.POSITIVE_INFINITY;
			switch (field) {
				case "abs":
					return (x:Dynamic) -> {
						checkNum(x, "Math.abs");
						return Math.abs(x);
					};
				case "sin":
					return (x:Dynamic) -> {
						checkNum(x, "Math.sin");
						return Math.sin(x);
					};
				case "cos":
					return (x:Dynamic) -> {
						checkNum(x, "Math.cos");
						return Math.cos(x);
					};
				case "tan":
					return (x:Dynamic) -> {
						checkNum(x, "Math.tan");
						return Math.tan(x);
					};
				case "atan2":
					return (y:Dynamic, x:Dynamic) -> {
						checkNum(y, "Math.atan2", "y");
						checkNum(x, "Math.atan2", "x");
						return Math.atan2(y, x);
					};
				case "sqrt":
					return (x:Dynamic) -> {
						checkNum(x, "Math.sqrt");
						return Math.sqrt(x);
					};
				case "pow":
					return (v:Dynamic, exp:Dynamic) -> {
						checkNum(v, "Math.pow", "base");
						checkNum(exp, "Math.pow", "exponent");
						return Math.pow(v, exp);
					};
				case "floor":
					return (x:Dynamic) -> {
						checkNum(x, "Math.floor");
						return Math.floor(x);
					};
				case "ceil":
					return (x:Dynamic) -> {
						checkNum(x, "Math.ceil");
						return Math.ceil(x);
					};
				case "round":
					return (x:Dynamic) -> {
						checkNum(x, "Math.round");
						return Math.round(x);
					};
				case "random":
					return () -> Math.random();
				case "min":
					return (a:Dynamic, b:Dynamic) -> {
						checkNum(a, "Math.min", "a");
						checkNum(b, "Math.min", "b");
						return Math.min(a, b);
					};
				case "max":
					return (a:Dynamic, b:Dynamic) -> {
						checkNum(a, "Math.max", "a");
						checkNum(b, "Math.max", "b");
						return Math.max(a, b);
					};
				case "acos":
					return (x:Dynamic) -> {
						checkNum(x, "Math.acos");
						return Math.acos(x);
					};
				case "asin":
					return (x:Dynamic) -> {
						checkNum(x, "Math.asin");
						return Math.asin(x);
					};
				case "atan":
					return (x:Dynamic) -> {
						checkNum(x, "Math.atan");
						return Math.atan(x);
					};
				case "exp":
					return (x:Dynamic) -> {
						checkNum(x, "Math.exp");
						return Math.exp(x);
					};
				case "log":
					return (x:Dynamic) -> {
						checkNum(x, "Math.log");
						return Math.log(x);
					};
				case "isNaN":
					return (x:Dynamic) -> Math.isNaN(x);
				case "isFinite":
					return (x:Dynamic) -> Math.isFinite(x);
				default:
			}
		}
		if (Std.isOfType(obj, haxe.Constraints.IMap)) {
			var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
			switch (field) {
				case "exists":
					return (key:Dynamic) -> map.exists(key);
				case "get":
					return (key:Dynamic) -> map.get(key);
				case "set":
					return (key:Dynamic, val:Dynamic) -> {
						if (!map.exists(key)) {
							trackMemory(1);
						}
						map.set(key, val);
						return null;
					};
				case "remove":
					return (key:Dynamic) -> map.remove(key);
				case "clear":
					return () -> {
						map.clear();
						return null;
					};
				case "keys":
					return () -> map.keys();
				case "iterator":
					return () -> map.iterator();
				case "keyValueIterator":
					return () -> map.keyValueIterator();
				case "toString":
					return () -> map.toString();
				default:
			}
		}

		if (Std.isOfType(obj, HaxiomAbstractInstance)) {
			var inst:HaxiomAbstractInstance = cast obj;
			var abs = inst.abstractType;
			if (abs.fields.exists(field)) {
				var fDef = abs.fields.get(field);
				if (fDef.property != null && !isInsideAccessor(field)) {
					var getAccessor = fDef.property.get;
					if (getAccessor == "get") {
						var m = abs.methods.get("get_" + field);
						if (m != null) {
							return Reflect.callMethod(null, bindMethod(obj, m), []);
						}
					} else if (getAccessor == "null" || getAccessor == "never") {
						if (currentThis != obj) {
							throw 'Cannot access private property $field of abstract ${abs.name}';
						}
					}
				}
			}
			if (abs.methods.exists(field)) {
				var m = abs.methods.get(field);
				return bindMethod(obj, m);
			}
			return evalField(inst.underlyingValue, field, scope, pos);
		}

		if (Std.isOfType(obj, HaxiomInstance)) {
			var inst:HaxiomInstance = cast obj;
			var fDef = findFieldDef(inst.cls, field);
			if (fDef != null) {
				checkMemberAccess(inst.cls, fDef.isPublic, pos, field);
				if (fDef.property != null && !isInsideAccessor(field)) {
					var getAccessor = fDef.property.get;
					if (getAccessor == "get") {
						var m = findMethod(inst.cls, "get_" + field);
						if (m != null)
							return Reflect.callMethod(null, bindMethod(obj, m), []);
					} else if (getAccessor == "null" || getAccessor == "never") {
						if (!isContextInsideClass(inst.cls)) {
							throw 'Cannot access private property $field of class ${inst.cls.name}';
						}
					}
				}
			}
			if (inst.fields.exists(field))
				return inst.fields.get(field);

			var m = findMethod(inst.cls, field);
			if (m != null) {
				checkMemberAccess(inst.cls, m.isPublic, pos, field);
				return bindMethod(obj, m);
			}
			var usingRes = resolveUsing(obj, field);
			if (usingRes != null)
				return usingRes;
			throw 'Method or field "$field" not found on class ${inst.cls.name}';
		}

		if (Std.isOfType(obj, HaxiomClass)) {
			var cls:HaxiomClass = cast obj;
			var fDef = findFieldDef(cls, field);
			if (fDef != null) {
				checkMemberAccess(cls, fDef.isPublic, pos, field);
			}
			if (cls.staticFields.exists(field))
				return cls.staticFields.get(field);

			var m = findStaticMethod(cls, field);
			if (m != null) {
				checkMemberAccess(cls, m.isPublic, pos, field);
				return bindMethod(obj, m);
			}
			var usingRes = resolveUsing(obj, field);
			if (usingRes != null)
				return usingRes;
			throw 'Static method or field "$field" not found on class ${cls.name}';
		}

		if (Std.isOfType(obj, HaxiomEnum)) {
			var enm:HaxiomEnum = cast obj;
			if (enm.constructors.exists(field)) {
				var argsList = enm.constructors.get(field);
				if (argsList == null || argsList.length == 0) {
					return new HaxiomEnumInstance(enm, field, []);
				} else {
					var numArgs = argsList.length;
					return switch (numArgs) {
						case 0: () -> new HaxiomEnumInstance(enm, field, []);
						case 1: (a) -> new HaxiomEnumInstance(enm, field, [a]);
						case 2: (a, b) -> new HaxiomEnumInstance(enm, field, [a, b]);
						case 3: (a, b, c) -> new HaxiomEnumInstance(enm, field, [a, b, c]);
						case 4: (a, b, c, d) -> new HaxiomEnumInstance(enm, field, [a, b, c, d]);
						default: Reflect.makeVarArgs((callArgs:Array<Dynamic>) -> new HaxiomEnumInstance(enm, field, callArgs));
					};
				}
			}
			throw 'Constructor "$field" not found on enum ${enm.name}';
		}

		if (Std.isOfType(obj, HaxiomAbstract)) {
			var abs:HaxiomAbstract = cast obj;
			if (abs.staticFields.exists(field)) {
				return abs.staticFields.get(field);
			}
			if (abs.methods.exists(field)) {
				var m = abs.methods.get(field);
				if (m.isStatic) {
					return bindMethod(obj, m);
				}
			}
			throw 'Static method or field "$field" not found on abstract ${abs.name}';
		}

		// Custom FFI member resolution overrides
		for (resolver in this.ffi.memberResolvers) {
			var res = resolver(obj, field);
			if (res != null)
				return res;
		}

		// Native static field overrides (for static inline variables erased on target platforms)
		if (Std.isOfType(obj, Class)) {
			var className = Type.getClassName(cast obj);
			if (className != null && this.ffi.nativeStaticFields.exists(className)) {
				var fields = this.ffi.nativeStaticFields.get(className);
				if (fields.exists(field)) {
					return fields.get(field);
				}
			}
		}

		// Native Haxe reflection
		var f:Dynamic = null;
		try {
			f = Reflect.getProperty(obj, field);
		} catch (e:Dynamic) {}
		#if haxiom_debug
		if (field == "addEventListener") {
			trace("DEBUG evalField native addEventListener: getProperty=" + f);
		}
		#end
		if (f == null) {
			f = safeField(obj, field);
		}
		#if haxiom_debug
		if (field == "addEventListener") {
			trace("DEBUG evalField native addEventListener end: f=" + f);
		}
		#end

		// Check if this is an abstract method or property redirection closure/getter
		for (absName in this.ffi.exposedAbstracts.keys()) {
			var absInfo = this.ffi.exposedAbstracts.get(absName);
			var getterName = "get_" + field;
			var isGetter = absInfo.methods.indexOf(getterName) != -1;
			var methodName = isGetter ? getterName : field;

			if (absInfo.methods.indexOf(methodName) != -1) {
				var matchesType = false;
				switch (absInfo.underlying) {
					case "Int":
						matchesType = Std.isOfType(obj, Int);
					case "Float":
						matchesType = Std.isOfType(obj, Float);
					case "String":
						matchesType = Std.isOfType(obj, String);
					case "Bool":
						matchesType = Std.isOfType(obj, Bool);
					default:
						var cls = resolveNativeClass(absInfo.underlying);
						if (cls != null)
							matchesType = Std.isOfType(obj, cls);
				}

				if (matchesType) {
					var implCls = resolveAbstractImpl(absName, absInfo.implClass);
					if (implCls != null) {
						var m = Reflect.field(implCls, methodName);
						if (m != null) {
							if (isGetter) {
								return Reflect.callMethod(null, m, [obj]);
							} else {
								return Reflect.makeVarArgs(function(args:Array<Dynamic>) {
									return Reflect.callMethod(null, m, [obj].concat(args));
								});
							}
						}
					}
				}
			}
		}
		if (Reflect.isFunction(f)) {
			#if (cpp || hl || java || cs)
			return f;
			#else
			// Wrap the method to bind `this` to the receiver object.
			// This is required on targets like JavaScript and Neko where prototype/native methods
			// returned by Reflect.getProperty/Reflect.field are unbound.
			return Reflect.makeVarArgs(function(args) {
				return Reflect.callMethod(obj, f, args);
			});
			#end
		}
		if (f != null)
			return f;

		var usingRes = resolveUsing(obj, field);
		if (usingRes != null)
			return usingRes;
		return null;
	}

	function assignField(obj:Dynamic, field:String, val:Dynamic, scope:Scope, ?pos:Pos):Dynamic {
		if (obj == null)
			throw 'Cannot set field "$field" of null';

		if (importWhitelist != null) {
			var name = getClassNameOf(obj);
			if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
				throwSecurityErrorForUnwhitelistedClass(field, name);
			}
		}
		if (Std.isOfType(obj, HaxiomAbstractInstance)) {
			var inst:HaxiomAbstractInstance = cast obj;
			var abs = inst.abstractType;
			if (abs.fields.exists(field)) {
				var fDef = abs.fields.get(field);
				if (fDef.property != null && !isInsideAccessor(field)) {
					var setAccessor = fDef.property.set;
					if (setAccessor == "set") {
						var m = abs.methods.get("set_" + field);
						if (m != null) {
							return Reflect.callMethod(null, bindMethod(obj, m), [val]);
						}
					} else if (setAccessor == "null" || setAccessor == "never") {
						if (currentThis != obj) {
							throw 'Cannot write to private property $field of abstract ${abs.name}';
						}
					}
				}
			}
			return assignField(inst.underlyingValue, field, val, scope, pos);
		}

		if (Std.isOfType(obj, HaxiomInstance)) {
			var inst:HaxiomInstance = cast obj;
			var fDef = findFieldDef(inst.cls, field);
			if (fDef != null) {
				checkMemberAccess(inst.cls, fDef.isPublic, pos, field);
				if (fDef.property != null && !isInsideAccessor(field)) {
					var setAccessor = fDef.property.set;
					if (setAccessor == "set") {
						var m = findMethod(inst.cls, "set_" + field);
						if (m != null)
							return Reflect.callMethod(null, bindMethod(obj, m), [val]);
					} else if (setAccessor == "null" || setAccessor == "never") {
						if (!isContextInsideClass(inst.cls)) {
							throw 'Cannot write to private property $field of class ${inst.cls.name}';
						}
					}
				}
				if (fDef.isFinal) {
					if (currentConstructorInstance != inst) {
						throw 'Cannot reassign final field $field outside of constructor';
					}
				}
				if (fDef.type != null) {
					val = castOrCheckType(val, fDef.type, scope, inst.genericBindings);
				}
			}
			if (!inst.fields.exists(field)) {
				trackMemory(1);
			}
			inst.fields.set(field, val);
		} else {
			if (Std.isOfType(obj, HaxiomClass)) {
				var cls:HaxiomClass = cast obj;
				var fDef = findFieldDef(cls, field);
				if (fDef != null) {
					checkMemberAccess(cls, fDef.isPublic, pos, field);
					if (fDef.isFinal) {
						throw 'Cannot reassign static final field $field';
					}
					if (fDef.type != null) {
						val = castOrCheckType(val, fDef.type, scope);
					}
				}
				cls.staticFields.set(field, val);
			} else {
				// Check if this is an abstract setter redirection
				var setterResolved = false;
				for (absName in this.ffi.exposedAbstracts.keys()) {
					var absInfo = this.ffi.exposedAbstracts.get(absName);
					var setterName = "set_" + field;
					if (absInfo.methods.indexOf(setterName) != -1) {
						var matchesType = false;
						switch (absInfo.underlying) {
							case "Int":
								matchesType = Std.isOfType(obj, Int);
							case "Float":
								matchesType = Std.isOfType(obj, Float);
							case "String":
								matchesType = Std.isOfType(obj, String);
							case "Bool":
								matchesType = Std.isOfType(obj, Bool);
							default:
								var cls = resolveNativeClass(absInfo.underlying);
								if (cls != null)
									matchesType = Std.isOfType(obj, cls);
						}

						if (matchesType) {
							var implCls = resolveAbstractImpl(absName, absInfo.implClass);
							if (implCls != null) {
								var m = Reflect.field(implCls, setterName);
								if (m != null) {
									Reflect.callMethod(null, m, [obj, val]);
									setterResolved = true;
									break;
								}
							}
						}
					}
				}
				if (!setterResolved) {
					var assigned = false;
					for (assigner in this.ffi.memberAssigners) {
						if (assigner(obj, field, val)) {
							assigned = true;
							break;
						}
					}
					if (!assigned) {
						if (Type.typeof(obj) == TObject && !Reflect.hasField(obj, field)) {
							trackMemory(1);
						}
						Reflect.setProperty(obj, field, val);
					}
				}
			}
		}
		return val;
	}

	function eval(e:Expr, scope:Scope):Dynamic {
		if (e != null && e.pos != null)
			lastEvalPos = e.pos;
		var pos = e.pos;
		if (maxInstructions > 0 && ++instructionsCount > maxInstructions) {
			var fileInfo = pos != null && pos.file != null ? pos.file : "script";
			var lineVal = pos != null ? pos.line : 1;
			var colVal = pos != null ? pos.col : 1;
			var locationStr = 'Runtime Error: Instruction limit exceeded ($maxInstructions ops) at ' + fileInfo + ':' + lineVal + ':' + colVal;
			throw new haxiom.ScriptException("Instruction limit exceeded (possible infinite loop)", callStack.copy(), locationStr, lineVal, colVal, fileInfo);
		}
		#if haxiom_debug
		trace("AST eval: " + Std.string(e.def));
		#end
		switch (e.def) {
			case EValue(v):
				#if haxiom_debug
				trace("AST eval EValue: val=" + Std.string(v) + " typeof=" + Std.string(Type.typeof(v)));
				#end
				return v;

			case EEReg(pattern, flags):
				return new EReg(pattern, flags);

			case EIdent(name):
				var pathRes = tryResolveExpressionPath(e, scope);
				if (pathRes.success)
					return pathRes.value;

				if (name == "this") {
					if (inAbstractMethod && Std.isOfType(currentThis, HaxiomAbstractInstance)) {
						return (cast currentThis : HaxiomAbstractInstance).underlyingValue;
					}
					return currentThis;
				}
				if (scope.exists(name))
					return scope.get(name);

				// Implicit this field/method resolution
				if (currentThis != null) {
					if (Std.isOfType(currentThis, HaxiomInstance)) {
						var inst:HaxiomInstance = cast currentThis;
						var fDef = findFieldDef(inst.cls, name);
						if (fDef != null && fDef.property != null && fDef.property.get == "get" && !isInsideAccessor(name)) {
							var m = findMethod(inst.cls, "get_" + name);
							if (m != null)
								return Reflect.callMethod(null, bindMethod(currentThis, m), []);
						}
						if (inst.fields.exists(name))
							return inst.fields.get(name);

						var m = findMethod(inst.cls, name);
						if (m != null)
							return bindMethod(currentThis, m);
					} else if (Std.isOfType(currentThis, HaxiomClass)) {
						var cls:HaxiomClass = cast currentThis;
						var fDef = findFieldDef(cls, name);
						if (fDef != null && fDef.isStatic) {
							if (fDef.property != null && fDef.property.get == "get" && !isInsideAccessor(name)) {
								var m = findStaticMethod(cls, "get_" + name);
								if (m != null)
									return Reflect.callMethod(null, bindMethod(currentThis, m), []);
							}
							if (cls.staticFields.exists(name))
								return cls.staticFields.get(name);
						}
						var m = findStaticMethod(cls, name);
						if (m != null)
							return bindMethod(currentThis, m);
					} else {
						// Native Haxe object field
						var f = Reflect.field(currentThis, name);
						if (f != null) {
							return f;
						}
					}
				}

				if (externClasses.exists(name)) {
					var pStr = pos != null ? '${pos.file != null ? pos.file : "script"}:${pos.line}:${pos.col}' : "script";
					var errMsg = 'Runtime Error: Unbound Host Extern \'$name\' at $pStr';
					throw new haxiom.ScriptException('Unbound Host Extern \'$name\'', callStack.copy(), errMsg, pos.line, pos.col, pos.file != null ? pos.file : "script");
				}
				throw 'Identifier "$name" not found at ${pos.line}:${pos.col}';

			case EVar(name, type, expr, isFinal, meta):
				var processedExpr = ResourceCompiler.processResource(meta, type, expr, e.pos, null);
				var val = processedExpr != null ? eval(processedExpr, scope) : null;
				if (type != null) {
					val = castOrCheckType(val, type, scope);
				}
				scope.declare(name, val, type, isFinal);
				return val;

			case EAssign(target, expr):
				var val = eval(expr, scope);
				switch (target.def) {
					case EIdent(name):
						if (name == "this") {
							if (inAbstractMethod && Std.isOfType(currentThis, HaxiomAbstractInstance)) {
								(cast currentThis : HaxiomAbstractInstance).underlyingValue = val;
								return val;
							}
							throw "Cannot assign to 'this'";
						}
						if (scope.exists(name)) {
							scope.checkAndSet(name, val, this);
						} else if (currentThis != null) {
							// Assign to implicit this field
							if (Std.isOfType(currentThis, HaxiomInstance)) {
								var inst:HaxiomInstance = cast currentThis;
								var fDef = findFieldDef(inst.cls, name);
								if (fDef != null && fDef.property != null && fDef.property.set == "set" && !isInsideAccessor(name)) {
									var m = findMethod(inst.cls, "set_" + name);
									if (m != null)
										return Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
								}
								if (fDef != null && fDef.isFinal) {
									if (currentConstructorInstance != inst) {
										throw 'Cannot reassign final field $name outside of constructor';
									}
								}
								if (fDef != null && fDef.type != null) {
									val = castOrCheckType(val, fDef.type, scope, inst.genericBindings);
								}
								inst.fields.set(name, val);
							} else if (Std.isOfType(currentThis, HaxiomClass)) {
								var cls:HaxiomClass = cast currentThis;
								var fDef = findFieldDef(cls, name);
								if (fDef != null && fDef.isStatic) {
									if (fDef.property != null && fDef.property.set == "set" && !isInsideAccessor(name)) {
										var m = findStaticMethod(cls, "set_" + name);
										if (m != null)
											return Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
									}
									if (fDef.isFinal) {
										throw 'Cannot reassign static final field $name';
									}
									if (fDef.type != null) {
										val = castOrCheckType(val, fDef.type, scope);
									}
									cls.staticFields.set(name, val);
								} else {
									scope.declare(name, val);
								}
							} else if (Std.isOfType(currentThis, HaxiomAbstractInstance)) {
								var inst:HaxiomAbstractInstance = cast currentThis;
								var fDef = inst.abstractType.fields.get(name);
								if (fDef != null && fDef.property != null && fDef.property.set == "set" && !isInsideAccessor(name)) {
									var m = inst.abstractType.methods.get("set_" + name);
									if (m != null)
										return Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
								}
							} else {
								Reflect.setField(currentThis, name, val);
							}
						} else {
							scope.declare(name, val);
						}
						return val;
					case EField(objExpr, field):
						switch (objExpr.def) {
							case EIdent("super"):
								if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
									var inst:HaxiomInstance = cast currentThis;
									inst.fields.set(field, val);
									return val;
								}
								throw "Cannot use 'super' outside of a class instance";
							default:
						}
						var obj = eval(objExpr, scope);
						if (obj == null)
							throw 'Cannot write field "$field" of null';
						return assignField(obj, field, val, scope, e.pos);
					case ESafeField(objExpr, field):
						var obj = eval(objExpr, scope);
						if (obj == null)
							return null;
						return assignField(obj, field, val, scope, e.pos);
					case EBinop("[]", objExpr, indexExpr):
						var obj = eval(objExpr, scope);
						var idx = eval(indexExpr, scope);
						setSubscript(obj, idx, val);
						return val;
					default:
						throw "Invalid assignment target";
				}

			case EBinop(op, e1, e2):
				if (op == "&&") {
					var v1 = eval(e1, scope);
					if (!isTruthy(v1))
						return v1;
					return eval(e2, scope);
				}
				if (op == "||") {
					var v1 = eval(e1, scope);
					if (isTruthy(v1))
						return v1;
					return eval(e2, scope);
				}
				if (op == "?") {
					// Ternary is represented as: Binop("?", cond, Binop(":", e1, e2))
					var cond = eval(e1, scope);
					switch (e2.def) {
						case EBinop(":", left, right):
							if (isTruthy(cond))
								return eval(left, scope);
							return eval(right, scope);
						default: throw "Invalid ternary operator format";
					}
				}
				if (op == "[]") {
					var obj = eval(e1, scope);
					var idx = eval(e2, scope);
					return getSubscript(obj, idx);
				}

				if (op == "??") {
					var v1 = eval(e1, scope);
					if (v1 != null)
						return v1;
					return eval(e2, scope);
				}
				if (op == "...") {
					var v1 = eval(e1, scope);
					var v2 = eval(e2, scope);
					checkInt(v1, "IntIterator start");
					checkInt(v2, "IntIterator end");
					return new IntIterator(cast v1, cast v2);
				}

				var val1:Dynamic = eval(e1, scope);
				var val2:Dynamic = eval(e2, scope);
				var overloadRes = findAbstractBinopOverload(op, val1, val2);
				if (overloadRes.success)
					return overloadRes.value;

				var binopRes:Dynamic = null;
				switch (op) {
					case "+":
						if (TypeSystem.isString(val1) || TypeSystem.isString(val2)) {
							binopRes = Std.string(val1) + Std.string(val2);
						} else {
							binopRes = (val1 + val2 : Dynamic);
						}
					case "-": binopRes = (val1 - val2 : Dynamic);
					case "*": binopRes = (val1 * val2 : Dynamic);
					case "/": binopRes = (val1 / val2 : Dynamic);
					case "%": binopRes = (val1 % val2 : Dynamic);
					case "==": binopRes = (val1 == val2 : Dynamic);
					case "!=": binopRes = (val1 != val2 : Dynamic);
					case "<": binopRes = (val1 < val2 : Dynamic);
					case "<=": binopRes = (val1 <= val2 : Dynamic);
					case ">": binopRes = (val1 > val2 : Dynamic);
					case ">=": binopRes = (val1 >= val2 : Dynamic);
					case "&": binopRes = ((cast val1 : Int) & (cast val2 : Int) : Dynamic);
					case "|": binopRes = ((cast val1 : Int) | (cast val2 : Int) : Dynamic);
					case "^": binopRes = ((cast val1 : Int) ^ (cast val2 : Int) : Dynamic);
					case "<<": binopRes = ((cast val1 : Int) << (cast val2 : Int) : Dynamic);
					case ">>": binopRes = ((cast val1 : Int) >> (cast val2 : Int) : Dynamic);
					case ">>>": binopRes = ((cast val1 : Int) >>> (cast val2 : Int) : Dynamic);
					default: throw 'Unknown operator "$op"';
				}
				return binopRes;

			case EUnop(op, expr):
				if (op == "post++" || op == "post--") {
					var val = eval(expr, scope);
					if (Std.isOfType(val, HaxiomAbstractInstance)) {
						var overloadRes = findAbstractUnopOverload(op, val);
						if (overloadRes.success) {
							assign(expr, overloadRes.value, scope);
							return val;
						}
					}
					var nextVal = op == "post++" ? (cast val : Float) + 1 : (cast val : Float) - 1;
					assign(expr, nextVal, scope);
					return val;
				}
				var val = eval(expr, scope);
				var overloadRes = findAbstractUnopOverload(op, val);
				if (overloadRes.success) {
					if (op == "++" || op == "--") {
						assign(expr, overloadRes.value, scope);
					}
					return overloadRes.value;
				}
				var unopRes:Dynamic = null;
				switch (op) {
					case "!": unopRes = !(cast val : Bool);
					case "-": unopRes = -(cast val : Float);
					case "~": unopRes = ~(cast val : Int);
					case "++":
						var resVal = (cast val : Float) + 1;
						assign(expr, resVal, scope);
						unopRes = resVal;
					case "--":
						var resVal = (cast val : Float) - 1;
						assign(expr, resVal, scope);
						unopRes = resVal;
					default: throw 'Unknown unary operator "$op"';
				}
				return unopRes;

			case EField(objExpr, field):
				var pathRes = tryResolveExpressionPath(e, scope);
				if (pathRes.success)
					return pathRes.value;

				switch (objExpr.def) {
					case EIdent("super"):
						if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
							var inst:HaxiomInstance = cast currentThis;
							var parentCls = inst.cls.parent;
							var m = findMethod(parentCls, field);
							if (m != null)
								return bindMethod(currentThis, m);
							throw 'Parent method or field "$field" not found on class ${inst.cls.name}';
						}
						throw "Cannot use 'super' outside of a class instance";
					default:
				}
				var obj = eval(objExpr, scope);
				return evalField(obj, field, scope, pos);

			case ESafeField(objExpr, field):
				var pathRes = tryResolveExpressionPath(e, scope);
				if (pathRes.success)
					return pathRes.value;

				var obj = eval(objExpr, scope);
				if (obj == null)
					return null;
				return evalField(obj, field, scope, pos);

			case ECall(calleeExpr, argsExprs):
				switch (calleeExpr.def) {
					case EField(obj, field):
						if (field == "await" && obj != null) {
							switch (obj.def) {
								case EIdent("HaxiomHost"):
									throw "HaxiomHost.await is only supported in VM execution mode (useVM = true)";
								default:
							}
						}
					default:
				}
				switch (calleeExpr.def) {
					case EIdent("super"):
						if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
							var inst:HaxiomInstance = cast currentThis;
							var parentCls = inst.cls.parent;
							if (parentCls != null) {
								var constr = findMethod(parentCls, "new");
								if (constr != null) {
									var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
									var cScope = Scope.create(scope);
									cScope.declare("this", currentThis);
									for (i in 0...constr.args.length) {
										var arg = constr.args[i];
										var val = i < args.length ? args[i] : null;
										val = castOrCheckType(val, arg.type, cScope);
										cScope.declare(arg.name, val, arg.type);
									}
									var oldThis = currentThis;
									var oldConstrInst = currentConstructorInstance;
									currentConstructorInstance = inst;
									pushFrame(parentCls.name + ".new", constr.body != null ? constr.body.pos : {line: 1, col: 1});
									try {
										if (useVM || (constr.body == null && (constr : Dynamic).bytecodeChunk != null)) {
											var cDyn:Dynamic = constr;
											if (cDyn.bytecodeChunk == null && constr.body != null) {
												cDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(constr.body, constr.args, false, false, debugMode, "new");
											}
											haxiom.VM.runChunk(this, cDyn.bytecodeChunk, cScope, currentThis, parentCls.name + ".new", args);
										} else {
											eval(constr.body, cScope);
										}
										Scope.recycle(cScope);
									} catch (flow:ControlFlow) {
										Scope.recycle(cScope);
										switch (flow) {
											case Return(_):
											default: throw flow;
										}
									} catch (err:Dynamic) {
										Scope.recycle(cScope);
										throw err;
									}
									currentConstructorInstance = oldConstrInst;
									currentThis = oldThis;
								}
							}
							return null;
						}
						throw "Cannot call 'super' constructor outside of subclass constructor";
					default:
				}

				// Native Haxe object method call bound-this optimization
				var isSafe = false;
				var objExpr:Expr = null;
				var field:String = null;
				switch (calleeExpr.def) {
					case EField(oe, f):
						switch (oe.def) {
							case EIdent("super"): // skip
							default:
								objExpr = oe;
								field = f;
						}
					case ESafeField(oe, f):
						objExpr = oe;
						field = f;
						isSafe = true;
					default:
				}

				if (objExpr != null && field != null) {
					var obj:Dynamic = eval(objExpr, scope);
					if (obj == null) {
						if (isSafe)
							return null;
						throw 'Cannot call method "$field" of null';
					}

					if (!Std.isOfType(obj, HaxiomInstance) && !Std.isOfType(obj, HaxiomClass)) {
						// Native Haxe object method call optimization
						if (Std.isOfType(obj, String)) {
							var str:String = cast obj;
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "split":
									checkArgCount(args, 1, 1, "String.split");
									checkString(args[0], "String.split", "delimiter");
									return str.split(args[0]);
								case "indexOf":
									checkArgCount(args, 1, 2, "String.indexOf");
									checkString(args[0], "String.indexOf", "substring");
									if (args.length > 1)
										checkInt(args[1], "String.indexOf", "start index");
									return args.length > 1 ? str.indexOf(args[0], args[1]) : str.indexOf(args[0]);
								case "lastIndexOf":
									checkArgCount(args, 1, 2, "String.lastIndexOf");
									checkString(args[0], "String.lastIndexOf", "substring");
									if (args.length > 1)
										checkInt(args[1], "String.lastIndexOf", "start index");
									return args.length > 1 ? str.lastIndexOf(args[0], args[1]) : str.lastIndexOf(args[0]);
								case "charAt":
									checkArgCount(args, 1, 1, "String.charAt");
									checkInt(args[0], "String.charAt", "index");
									return str.charAt(args[0]);
								case "charCodeAt":
									checkArgCount(args, 1, 1, "String.charCodeAt");
									checkInt(args[0], "String.charCodeAt", "index");
									return str.charCodeAt(args[0]);
								case "substring":
									checkArgCount(args, 1, 2, "String.substring");
									checkInt(args[0], "String.substring", "start index");
									if (args.length > 1)
										checkInt(args[1], "String.substring", "end index");
									return args.length > 1 ? str.substring(args[0], args[1]) : str.substring(args[0]);
								case "substr":
									checkArgCount(args, 1, 2, "String.substr");
									checkInt(args[0], "String.substr", "start index");
									if (args.length > 1)
										checkInt(args[1], "String.substr", "length");
									return args.length > 1 ? str.substr(args[0], args[1]) : str.substr(args[0]);
								case "toLowerCase":
									checkArgCount(args, 0, 0, "String.toLowerCase");
									return str.toLowerCase();
								case "toUpperCase":
									checkArgCount(args, 0, 0, "String.toUpperCase");
									return str.toUpperCase();
								case "toString":
									checkArgCount(args, 0, 0, "String.toString");
									return str;
								case "startsWith":
									checkArgCount(args, 1, 1, "StringTools.startsWith");
									checkString(args[0], "StringTools.startsWith", "prefix");
									return StringTools.startsWith(str, args[0]);
								case "endsWith":
									checkArgCount(args, 1, 1, "StringTools.endsWith");
									checkString(args[0], "StringTools.endsWith", "suffix");
									return StringTools.endsWith(str, args[0]);
								case "trim":
									checkArgCount(args, 0, 0, "StringTools.trim");
									return StringTools.trim(str);
								case "ltrim":
									checkArgCount(args, 0, 0, "StringTools.ltrim");
									return StringTools.ltrim(str);
								case "rtrim":
									checkArgCount(args, 0, 0, "StringTools.rtrim");
									return StringTools.rtrim(str);
								case "replace":
									checkArgCount(args, 2, 2, "StringTools.replace");
									checkString(args[0], "StringTools.replace", "sub");
									checkString(args[1], "StringTools.replace", "by");
									return StringTools.replace(str, args[0], args[1]);
								case "lpad":
									checkArgCount(args, 2, 2, "StringTools.lpad");
									checkString(args[0], "StringTools.lpad", "char");
									checkInt(args[1], "StringTools.lpad", "length");
									return StringTools.lpad(str, args[0], args[1]);
								case "rpad":
									checkArgCount(args, 2, 2, "StringTools.rpad");
									checkString(args[0], "StringTools.rpad", "char");
									checkInt(args[1], "StringTools.rpad", "length");
									return StringTools.rpad(str, args[0], args[1]);
								case "urlEncode":
									checkArgCount(args, 0, 0, "StringTools.urlEncode");
									return StringTools.urlEncode(str);
								case "urlDecode":
									checkArgCount(args, 0, 0, "StringTools.urlDecode");
									return StringTools.urlDecode(str);
								case "htmlEscape":
									checkArgCount(args, 0, 1, "StringTools.htmlEscape");
									if (args.length > 0 && !Std.isOfType(args[0], Bool))
										throw "StringTools.htmlEscape expected a Bool for quotes";
									return args.length > 0 ? StringTools.htmlEscape(str, args[0]) : StringTools.htmlEscape(str);
								case "htmlUnescape":
									checkArgCount(args, 0, 0, "StringTools.htmlUnescape");
									return StringTools.htmlUnescape(str);
								default:
							}
						}
						if (Std.isOfType(obj, Array)) {
							var arr:Array<Dynamic> = cast obj;
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "concat":
									checkArgCount(args, 1, 1, "Array.concat");
									if (!Std.isOfType(args[0], Array))
										throw "Array.concat expected an Array but got " + getTypeName(args[0]);
									return arr.concat(args[0]);
								case "push":
									checkArgCount(args, 1, 1, "Array.push");
									return arr.push(args[0]);
								case "pop":
									checkArgCount(args, 0, 0, "Array.pop");
									return arr.pop();
								case "shift":
									checkArgCount(args, 0, 0, "Array.shift");
									return arr.shift();
								case "unshift":
									checkArgCount(args, 1, 1, "Array.unshift");
									arr.unshift(args[0]);
									return null;
								case "remove":
									checkArgCount(args, 1, 1, "Array.remove");
									return arr.remove(args[0]);
								case "indexOf":
									checkArgCount(args, 1, 2, "Array.indexOf");
									if (args.length > 1)
										checkInt(args[1], "Array.indexOf", "start index");
									return args.length > 1 ? arr.indexOf(args[0], args[1]) : arr.indexOf(args[0]);
								case "lastIndexOf":
									checkArgCount(args, 1, 2, "Array.lastIndexOf");
									if (args.length > 1)
										checkInt(args[1], "Array.lastIndexOf", "start index");
									return args.length > 1 ? arr.lastIndexOf(args[0], args[1]) : arr.lastIndexOf(args[0]);
								case "insert":
									checkArgCount(args, 2, 2, "Array.insert");
									checkInt(args[0], "Array.insert", "index");
									arr.insert(args[0], args[1]);
									return null;
								case "reverse":
									checkArgCount(args, 0, 0, "Array.reverse");
									arr.reverse();
									return null;
								case "sort":
									checkArgCount(args, 1, 1, "Array.sort");
									checkFunction(args[0], "Array.sort", "comparator");
									arr.sort((a, b) -> Reflect.callMethod(null, args[0], [a, b]));
									return null;
								case "resize":
									checkArgCount(args, 1, 1, "Array.resize");
									checkInt(args[0], "Array.resize", "length");
									arr.resize(args[0]);
									return null;
								case "contains":
									checkArgCount(args, 1, 1, "Array.contains");
									return arr.contains(args[0]);
								case "join":
									checkArgCount(args, 1, 1, "Array.join");
									checkString(args[0], "Array.join", "separator");
									return arr.join(args[0]);
								case "slice":
									checkArgCount(args, 1, 2, "Array.slice");
									checkInt(args[0], "Array.slice", "start index");
									if (args.length > 1)
										checkInt(args[1], "Array.slice", "end index");
									return args.length > 1 ? arr.slice(args[0], args[1]) : arr.slice(args[0]);
								case "copy":
									checkArgCount(args, 0, 0, "Array.copy");
									return arr.copy();
								case "filter":
									checkArgCount(args, 1, 1, "Array.filter");
									checkFunction(args[0], "Array.filter", "callback");
									return arr.filter((x) -> Reflect.callMethod(null, args[0], [x]));
								case "map":
									checkArgCount(args, 1, 1, "Array.map");
									checkFunction(args[0], "Array.map", "callback");
									return arr.map((x) -> Reflect.callMethod(null, args[0], [x]));
								case "toString":
									checkArgCount(args, 0, 0, "Array.toString");
									return arr.toString();
								case "iterator":
									checkArgCount(args, 0, 0, "Array.iterator");
									return arr.iterator();
								case "keyValueIterator":
									checkArgCount(args, 0, 0, "Array.keyValueIterator");
									return arr.keyValueIterator();
								default:
							}
						}
						if (Std.isOfType(obj, haxe.ds.List)) {
							var list:haxe.ds.List<Dynamic> = cast obj;
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "add":
									checkArgCount(args, 1, 1, "List.add");
									list.add(args[0]);
									return null;
								case "push":
									checkArgCount(args, 1, 1, "List.push");
									list.push(args[0]);
									return null;
								case "first":
									checkArgCount(args, 0, 0, "List.first");
									return list.first();
								case "last":
									checkArgCount(args, 0, 0, "List.last");
									return list.last();
								case "pop":
									checkArgCount(args, 0, 0, "List.pop");
									return list.pop();
								case "isEmpty":
									checkArgCount(args, 0, 0, "List.isEmpty");
									return list.isEmpty();
								case "clear":
									checkArgCount(args, 0, 0, "List.clear");
									list.clear();
									return null;
								case "remove":
									checkArgCount(args, 1, 1, "List.remove");
									return list.remove(args[0]);
								case "iterator":
									checkArgCount(args, 0, 0, "List.iterator");
									return list.iterator();
								case "toString":
									checkArgCount(args, 0, 0, "List.toString");
									return list.toString();
								case "join":
									checkArgCount(args, 1, 1, "List.join");
									checkString(args[0], "List.join", "separator");
									return list.join(args[0]);
								case "filter":
									checkArgCount(args, 1, 1, "List.filter");
									checkFunction(args[0], "List.filter", "callback");
									return list.filter((x) -> Reflect.callMethod(null, args[0], [x]));
								case "map":
									checkArgCount(args, 1, 1, "List.map");
									checkFunction(args[0], "List.map", "callback");
									return list.map((x) -> Reflect.callMethod(null, args[0], [x]));
								default:
							}
						}
						if (obj == String) {
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "fromCharCode":
									checkArgCount(args, 1, 1, "String.fromCharCode");
									checkInt(args[0], "String.fromCharCode", "code");
									return String.fromCharCode(args[0]);
								default:
							}
						}
						if (obj == StringTools) {
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "urlEncode":
									checkArgCount(args, 1, 1, "StringTools.urlEncode");
									checkString(args[0], "StringTools.urlEncode", "s");
									return StringTools.urlEncode(args[0]);
								case "urlDecode":
									checkArgCount(args, 1, 1, "StringTools.urlDecode");
									checkString(args[0], "StringTools.urlDecode", "s");
									return StringTools.urlDecode(args[0]);
								case "htmlEscape":
									checkArgCount(args, 1, 2, "StringTools.htmlEscape");
									checkString(args[0], "StringTools.htmlEscape", "s");
									if (args.length > 1 && !Std.isOfType(args[1], Bool))
										throw "StringTools.htmlEscape expected a Bool for quotes";
									return args.length > 1 ? StringTools.htmlEscape(args[0], args[1]) : StringTools.htmlEscape(args[0]);
								case "htmlUnescape":
									checkArgCount(args, 1, 1, "StringTools.htmlUnescape");
									checkString(args[0], "StringTools.htmlUnescape", "s");
									return StringTools.htmlUnescape(args[0]);
								case "hex":
									checkArgCount(args, 1, 2, "StringTools.hex");
									checkInt(args[0], "StringTools.hex", "n");
									if (args.length > 1)
										checkInt(args[1], "StringTools.hex", "digits");
									return args.length > 1 ? StringTools.hex(args[0], args[1]) : StringTools.hex(args[0]);
								case "fastCodeAt":
									checkArgCount(args, 2, 2, "StringTools.fastCodeAt");
									checkString(args[0], "StringTools.fastCodeAt", "s");
									checkInt(args[1], "StringTools.fastCodeAt", "index");
									return StringTools.fastCodeAt(args[0], args[1]);
								case "isSpace":
									checkArgCount(args, 2, 2, "StringTools.isSpace");
									checkString(args[0], "StringTools.isSpace", "s");
									checkInt(args[1], "StringTools.isSpace", "index");
									return StringTools.isSpace(args[0], args[1]);
								case "trim":
									checkArgCount(args, 1, 1, "StringTools.trim");
									checkString(args[0], "StringTools.trim", "s");
									return StringTools.trim(args[0]);
								case "ltrim":
									checkArgCount(args, 1, 1, "StringTools.ltrim");
									checkString(args[0], "StringTools.ltrim", "s");
									return StringTools.ltrim(args[0]);
								case "rtrim":
									checkArgCount(args, 1, 1, "StringTools.rtrim");
									checkString(args[0], "StringTools.rtrim", "s");
									return StringTools.rtrim(args[0]);
								case "replace":
									checkArgCount(args, 3, 3, "StringTools.replace");
									checkString(args[0], "StringTools.replace", "s");
									checkString(args[1], "StringTools.replace", "sub");
									checkString(args[2], "StringTools.replace", "by");
									return StringTools.replace(args[0], args[1], args[2]);
								case "startsWith":
									checkArgCount(args, 2, 2, "StringTools.startsWith");
									checkString(args[0], "StringTools.startsWith", "s");
									checkString(args[1], "StringTools.startsWith", "prefix");
									return StringTools.startsWith(args[0], args[1]);
								case "endsWith":
									checkArgCount(args, 2, 2, "StringTools.endsWith");
									checkString(args[0], "StringTools.endsWith", "s");
									checkString(args[1], "StringTools.endsWith", "suffix");
									return StringTools.endsWith(args[0], args[1]);
								case "lpad":
									checkArgCount(args, 3, 3, "StringTools.lpad");
									checkString(args[0], "StringTools.lpad", "s");
									checkString(args[1], "StringTools.lpad", "char");
									checkInt(args[2], "StringTools.lpad", "length");
									return StringTools.lpad(args[0], args[1], args[2]);
								case "rpad":
									checkArgCount(args, 3, 3, "StringTools.rpad");
									checkString(args[0], "StringTools.rpad", "s");
									checkString(args[1], "StringTools.rpad", "char");
									checkInt(args[2], "StringTools.rpad", "length");
									return StringTools.rpad(args[0], args[1], args[2]);
								default:
							}
						}
						if (obj == Math) {
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "abs":
									checkArgCount(args, 1, 1, "Math.abs");
									checkNum(args[0], "Math.abs");
									return Math.abs(args[0]);
								case "sin":
									checkArgCount(args, 1, 1, "Math.sin");
									checkNum(args[0], "Math.sin");
									return Math.sin(args[0]);
								case "cos":
									checkArgCount(args, 1, 1, "Math.cos");
									checkNum(args[0], "Math.cos");
									return Math.cos(args[0]);
								case "tan":
									checkArgCount(args, 1, 1, "Math.tan");
									checkNum(args[0], "Math.tan");
									return Math.tan(args[0]);
								case "atan2":
									checkArgCount(args, 2, 2, "Math.atan2");
									checkNum(args[0], "Math.atan2", "y");
									checkNum(args[1], "Math.atan2", "x");
									return Math.atan2(args[0], args[1]);
								case "sqrt":
									checkArgCount(args, 1, 1, "Math.sqrt");
									checkNum(args[0], "Math.sqrt");
									return Math.sqrt(args[0]);
								case "pow":
									checkArgCount(args, 2, 2, "Math.pow");
									checkNum(args[0], "Math.pow", "base");
									checkNum(args[1], "Math.pow", "exponent");
									return Math.pow(args[0], args[1]);
								case "floor":
									checkArgCount(args, 1, 1, "Math.floor");
									checkNum(args[0], "Math.floor");
									return Math.floor(args[0]);
								case "ceil":
									checkArgCount(args, 1, 1, "Math.ceil");
									checkNum(args[0], "Math.ceil");
									return Math.ceil(args[0]);
								case "round":
									checkArgCount(args, 1, 1, "Math.round");
									checkNum(args[0], "Math.round");
									return Math.round(args[0]);
								case "random":
									checkArgCount(args, 0, 0, "Math.random");
									return Math.random();
								case "min":
									checkArgCount(args, 2, 2, "Math.min");
									checkNum(args[0], "Math.min", "a");
									checkNum(args[1], "Math.min", "b");
									return Math.min(args[0], args[1]);
								case "max":
									checkArgCount(args, 2, 2, "Math.max");
									checkNum(args[0], "Math.max", "a");
									checkNum(args[1], "Math.max", "b");
									return Math.max(args[0], args[1]);
								case "acos":
									checkArgCount(args, 1, 1, "Math.acos");
									checkNum(args[0], "Math.acos");
									return Math.acos(args[0]);
								case "asin":
									checkArgCount(args, 1, 1, "Math.asin");
									checkNum(args[0], "Math.asin");
									return Math.asin(args[0]);
								case "atan":
									checkArgCount(args, 1, 1, "Math.atan");
									checkNum(args[0], "Math.atan");
									return Math.atan(args[0]);
								case "exp":
									checkArgCount(args, 1, 1, "Math.exp");
									checkNum(args[0], "Math.exp");
									return Math.exp(args[0]);
								case "log":
									checkArgCount(args, 1, 1, "Math.log");
									checkNum(args[0], "Math.log");
									return Math.log(args[0]);
								case "isNaN":
									checkArgCount(args, 1, 1, "Math.isNaN");
									return Math.isNaN(args[0]);
								case "isFinite":
									checkArgCount(args, 1, 1, "Math.isFinite");
									return Math.isFinite(args[0]);
								default:
							}
						}
						if (obj == Date) {
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "now":
									checkArgCount(args, 0, 0, "Date.now");
									return Date.now();
								case "fromTime":
									checkArgCount(args, 1, 1, "Date.fromTime");
									checkNum(args[0], "Date.fromTime");
									return Date.fromTime(args[0]);
								case "fromString":
									checkArgCount(args, 1, 1, "Date.fromString");
									checkString(args[0], "Date.fromString", "s");
									return Date.fromString(args[0]);
								default:
							}
						}
						if (Std.isOfType(obj, haxe.Constraints.IMap)) {
							var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							switch (field) {
								case "exists":
									checkArgCount(args, 1, 1, "Map.exists");
									return map.exists(args[0]);
								case "get":
									checkArgCount(args, 1, 1, "Map.get");
									return map.get(args[0]);
								case "set":
									checkArgCount(args, 2, 2, "Map.set");
									map.set(args[0], args[1]);
									return null;
								case "remove":
									checkArgCount(args, 1, 1, "Map.remove");
									return map.remove(args[0]);
								case "clear":
									checkArgCount(args, 0, 0, "Map.clear");
									map.clear();
									return null;
								case "keys":
									checkArgCount(args, 0, 0, "Map.keys");
									return map.keys();
								case "iterator":
									checkArgCount(args, 0, 0, "Map.iterator");
									return map.iterator();
								case "keyValueIterator":
									checkArgCount(args, 0, 0, "Map.keyValueIterator");
									return map.keyValueIterator();
								case "toString":
									checkArgCount(args, 0, 0, "Map.toString");
									return map.toString();
								default:
							}
						}
						if (importWhitelist != null) {
							var name = getClassNameOf(obj);
							if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
								throwSecurityErrorForUnwhitelistedClass(field, name);
							}
						}
						var method = Reflect.field(obj, field);
						if (method == null) {
							method = Reflect.getProperty(obj, field);
						}
						if (obj == haxe.Json && field == "stringify") {
							method = (cast function(value:Dynamic, ?replacer:Dynamic, ?space:String):String {
								checkSafeToSerialize(value);
								return haxe.Json.stringify(value, replacer, space);
							} : Dynamic);
						}
						if (obj == haxe.Serializer && field == "run") {
							method = (cast function(v:Dynamic) {
								checkSafeToSerialize(v);
								return haxe.Serializer.run(v);
							} : Dynamic);
						}
						if (Std.isOfType(obj, haxe.Serializer) && field == "serialize") {
							method = (cast function(v:Dynamic) {
								checkSafeToSerialize(v);
								var serializer:haxe.Serializer = cast obj;
								serializer.serialize(v);
							} : Dynamic);
						}
						if (method != null && Reflect.isFunction(method)) {
							var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
							return Reflect.callMethod(obj, method, args);
						}

						// Check if this is an abstract method redirection call
						for (absName in this.ffi.exposedAbstracts.keys()) {
							var absInfo = this.ffi.exposedAbstracts.get(absName);
							if (absInfo.methods.indexOf(field) != -1) {
								var matchesType = false;
								switch (absInfo.underlying) {
									case "Int": matchesType = Std.isOfType(obj, Int);
									case "Float": matchesType = Std.isOfType(obj, Float);
									case "String": matchesType = Std.isOfType(obj, String);
									case "Bool": matchesType = Std.isOfType(obj, Bool);
									default:
										var cls = resolveNativeClass(absInfo.underlying);
										if (cls != null) matchesType = Std.isOfType(obj, cls);
								}

								if (matchesType) {
									var implCls = resolveAbstractImpl(absName, absInfo.implClass);
									if (implCls != null) {
										var m = Reflect.field(implCls, field);
										if (m != null) {
											var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];
											return Reflect.callMethod(null, m, [obj].concat(args));
										}
									}
								}
							}
						}
					}
				}

				var callee = eval(calleeExpr, scope);
				var args:Array<Dynamic> = [for (a in argsExprs) eval(a, scope)];

				if (Reflect.isFunction(callee) && safeGetClassName(callee) == null) {
					return Reflect.callMethod(null, callee, args);
				}

				if (Std.isOfType(callee, HaxiomClass)) {
					// Instantiate Haxiom class
					var cls:HaxiomClass = cast callee;
					var inst = new HaxiomInstance(cls);

					// Initialize default instance fields
					var curr = cls;
					while (curr != null) {
						for (f in curr.fields) {
							if (!f.isStatic) {
								inst.fields.set(f.name, f.expr != null ? eval(f.expr, scope) : null);
							}
						}
						curr = curr.parent;
					}

					// Run constructor 'new'
					var constr = findMethod(cls, "new");
					if (constr != null) {
						checkMemberAccess(cls, constr.isPublic, e.pos, "new");
						var cScope = Scope.create(scope);
						cScope.declare("this", inst);
						for (i in 0...constr.args.length) {
							var arg = constr.args[i];
							var val = i < args.length ? args[i] : null;
							val = castOrCheckType(val, arg.type, cScope);
							cScope.declare(arg.name, val, arg.type);
						}
						var oldThis = currentThis;
						currentThis = inst;
						var oldConstrInst = currentConstructorInstance;
						currentConstructorInstance = inst;
						pushFrame(cls.name + ".new", constr.body != null ? constr.body.pos : {line: 1, col: 1});
						try {
							if (useVM || (constr.body == null && (constr : Dynamic).bytecodeChunk != null)) {
								var cDyn:Dynamic = constr;
								if (cDyn.bytecodeChunk == null && constr.body != null) {
									cDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(constr.body, constr.args, false, false, debugMode, "new");
								}
								haxiom.VM.runChunk(this, cDyn.bytecodeChunk, cScope, inst, cls.name + ".new", args);
							} else {
								eval(constr.body, cScope);
							}
							popFrame();
							Scope.recycle(cScope);
						} catch (e:ControlFlow) {
							popFrame();
							Scope.recycle(cScope);
							switch (e) {
								case Return(_): // constructors return instance implicitly
								default: throw e;
							}
						} catch (err:Dynamic) {
							popFrame();
							Scope.recycle(cScope);
							throw err;
						}
						currentConstructorInstance = oldConstrInst;
						currentThis = oldThis;
					}
					return inst;
				}

				if (callee == null) {
					throw "Callee is null or undefined";
				}

				var calleeClassName = safeGetClassName(callee);
				if (calleeClassName != null) {
					switch (calleeClassName) {
						case "haxe.ds.StringMap":
							return new haxe.ds.StringMap<Dynamic>();
						case "haxe.ds.IntMap":
							return new haxe.ds.IntMap<Dynamic>();
						case "haxe.ds.ObjectMap":
							return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
						default:
							return Type.createInstance(cast callee, args);
					}
				}

				throw "Callee is not a callable function or constructor";

			case ENew(typeDecl, argsExprs):
				var inst = evalNew(typeDecl, argsExprs, scope, pos);
				trackNewAllocation(inst, pos);
				return inst;

			case EArrayDecl(values):
				var arr = [for (v in values) eval(v, scope)];
				trackNewAllocation(arr, pos);
				return arr;

			case EObjectDecl(fields):
				var obj = {};
				for (f in fields) {
					Reflect.setField(obj, f.name, eval(f.expr, scope));
				}
				trackNewAllocation(obj, pos);
				return obj;

			case EMapDecl(values):
				if (values.length == 0) {
					var m = new haxiom.DynamicMap();
					trackNewAllocation(m, pos);
					return m;
				}
				var evaluated = [];
				var allString = true;
				var allInt = true;
				for (kv in values) {
					var k = eval(kv.key, scope);
					var v = eval(kv.value, scope);
					evaluated.push({key: k, value: v});
					if (!Std.isOfType(k, String))
						allString = false;
					if (!Std.isOfType(k, Int))
						allInt = false;
				}
				var map:haxe.Constraints.IMap<Dynamic, Dynamic> = null;
				if (allString) {
					map = new haxe.ds.StringMap<Dynamic>();
				} else if (allInt) {
					map = new haxe.ds.IntMap<Dynamic>();
				} else {
					map = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
				}
				for (kv in evaluated) {
					map.set(kv.key, kv.value);
				}
				trackNewAllocation(map, pos);
				return map;

			case EClass(name, fields, methods, parentType, interfaceTypes, params, meta, isExternClass):
				var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
				if (isExternClass == true) {
					externClasses.set(fqName, true);
					externClasses.set(name, true);
					return null;
				}
				var parentCls:HaxiomClass = null;
				if (parentType != null) {
					switch (parentType) {
						case TPath(path, _):
							var parentName = path.join(".");
							if (externClasses.exists(parentName)) {
								throw new haxiom.CompileException('Cannot extend extern class \'$parentName\'', e.pos.line, e.pos.col, e.pos.file != null ? e.pos.file : "script");
							}
							var parentVal = scope.get(parentName);
							if (parentVal != null && Std.isOfType(parentVal, HaxiomClass)) {
								parentCls = cast parentVal;
							}
						default:
					}
				}
				var cls = new HaxiomClass(name, parentCls);
				cls.name = fqName;
				cls.parentType = parentType;
				cls.params = params != null ? params : [];
				cls.interfaces = interfaceTypes != null ? interfaceTypes : [];
				cls.meta = evaluateMetadata(meta, scope);
				
				var hasAbstractMeta = false;
				if (cls.meta != null) {
					for (m in cls.meta) {
						if (m.name == ":abstract") {
							hasAbstractMeta = true;
							break;
						}
					}
				}
				cls.isAbstract = hasAbstractMeta;

				for (f in fields) {
					var fieldExpr = f.expr;
					if (f.meta != null) {
						fieldExpr = ResourceCompiler.processResource(f.meta, f.type, f.expr, e.pos, null);
					}
					cls.fields.set(f.name, {
						name: f.name,
						type: f.type,
						expr: fieldExpr,
						isStatic: f.isStatic,
						isPublic: f.isPublic,
						isFinal: f.isFinal,
						property: f.property,
						meta: evaluateMetadata(f.meta, scope)
					});
					if (f.isStatic && fieldExpr != null) {
						cls.staticFields.set(f.name, eval(fieldExpr, scope));
					}
				}
				for (m in methods) {
					var mDyn:Dynamic = m;
					cls.methods.set(m.name, {
						name: m.name,
						args: m.args,
						retType: m.retType,
						body: m.body,
						isStatic: m.isStatic,
						isPublic: m.isPublic,
						isOverride: mDyn.isOverride,
						isAbstract: mDyn.isAbstract,
						bytecodeChunk: mDyn.bytecodeChunk,
						meta: evaluateMetadata(m.meta, scope)
					});
				}

				// 1. Runtime override checks
				for (mName in cls.methods.keys()) {
					var m = cls.methods.get(mName);
					var parentMethod = findMethod(cls.parent, mName);
					if (m.isOverride) {
						if (parentMethod == null) {
							throw new haxiom.CompileException('Method ${mName} is marked override but no parent class method was found', 0, 0, fqName);
						} else if (parentMethod.isAbstract == true) {
							throw new haxiom.CompileException('Method ${mName} overrides an abstract method and must not use the override keyword', 0, 0, fqName);
						}
					} else {
						if (parentMethod != null && parentMethod.isAbstract != true && mName != "new") {
							throw new haxiom.CompileException('Field ${mName} overrides parent class field and requires the override keyword', 0, 0, fqName);
						}
					}
				}

				// 2. Runtime concrete class abstract implementation checks
				if (!cls.isAbstract) {
					var currentParent = cls.parent;
					var abstractMethods = new Map<String, String>();
					while (currentParent != null) {
						for (mName in currentParent.methods.keys()) {
							var m = currentParent.methods.get(mName);
							if (m.isAbstract) {
								if (!abstractMethods.exists(mName)) {
									abstractMethods.set(mName, currentParent.name);
								}
							}
						}
						currentParent = currentParent.parent;
					}

					for (mName in abstractMethods.keys()) {
						var implemented = false;
						var current = cls;
						while (current != null) {
							if (current.methods.exists(mName)) {
								var m = current.methods.get(mName);
								if (!m.isAbstract) {
									implemented = true;
									break;
								}
							}
							current = current.parent;
						}
						if (!implemented) {
							throw new haxiom.CompileException('Class ${name} must implement abstract method ${mName} of parent class ${abstractMethods.get(mName)}', 0, 0, fqName);
						}
					}
				}

				var implementedInterfaces = interfaceTypes != null ? interfaceTypes : [];
				if (implementedInterfaces.length > 0) {
					for (itfDecl in implementedInterfaces) {
						switch (itfDecl) {
							case TPath(itfPath, itfConcreteParams):
								var itfName = itfPath.join(".");
								var itfVal = scope.get(itfName);
								if (itfVal != null
									&& (Reflect.hasField(itfVal, "__isInterface") || !Std.isOfType(itfVal, HaxiomInterface))) {
									if (Reflect.hasField(itfVal, "__isInterface")
										|| Std.isOfType(itfVal, Class)
										|| Std.isOfType(itfVal, Enum)) {
										continue;
									}
								}
								if (itfVal == null || !Std.isOfType(itfVal, HaxiomInterface)) {
									throw 'Interface $itfName not found at ${pos.line}:${pos.col}';
								}
								var itf:HaxiomInterface = cast itfVal;

								var itfBindings = new Map<String, TypeDecl>();
								if (itf.params != null) {
									for (i in 0...itf.params.length) {
										var paramName = itf.params[i].name;
										var boundType = (itfConcreteParams != null && i < itfConcreteParams.length) ? itfConcreteParams[i] : TPath(["Dynamic"],
											[]);
										itfBindings.set(itf.name + "." + paramName, boundType);
									}
								}

								var allItfMethods = new Map<String, {method:{
									name:String,
									args:Array<FunctionArg>,
									retType:Null<TypeDecl>,
									?body:Null<Expr>,
									?meta:Array<{name:String, params:Array<Dynamic>}>
								}, bindings:Map<String, TypeDecl>}>();
								var allItfFields = new Map<String, {field:{
									name:String,
									type:Null<TypeDecl>,
									?property:{get:String, set:String},
									?meta:Array<{name:String, params:Array<Dynamic>}>
								}, bindings:Map<String, TypeDecl>}>();
								var visitedItf = new Map();
								function collectMethodsAndFields(currItf:HaxiomInterface, currentItfBindings:Map<String, TypeDecl>) {
									if (visitedItf.exists(currItf.name))
										return;
									visitedItf.set(currItf.name, true);
									for (mKey in currItf.methods.keys()) {
										if (!allItfMethods.exists(mKey)) {
											allItfMethods.set(mKey, {method: currItf.methods.get(mKey), bindings: currentItfBindings});
										}
									}
									for (fKey in currItf.fields.keys()) {
										if (!allItfFields.exists(fKey)) {
											allItfFields.set(fKey, {field: currItf.fields.get(fKey), bindings: currentItfBindings});
										}
									}
									for (p in currItf.parents) {
										switch (p) {
											case TPath(pPath, pConcreteParams):
												var pName = pPath.join(".");
												var pItfVal = scope.get(pName);
												if (pItfVal != null && Std.isOfType(pItfVal, HaxiomInterface)) {
													var pItf:HaxiomInterface = cast pItfVal;
													var pBindings = new Map<String, TypeDecl>();
													if (pItf.params != null) {
														for (i in 0...pItf.params.length) {
															var paramName = pItf.params[i].name;
															var boundType = (pConcreteParams != null && i < pConcreteParams.length) ? pConcreteParams[i] : TPath(["Dynamic"],
																[]);
															boundType = resolveGenericType(boundType, currentItfBindings, scope);
															pBindings.set(pItf.name + "." + paramName, boundType);
														}
													}
													collectMethodsAndFields(pItf, pBindings);
												}
											default:
										}
									}
								}
								collectMethodsAndFields(itf, itfBindings);

								for (itfKey in allItfFields.keys()) {
									var itfData = allItfFields.get(itfKey);
									var itfField = itfData.field;
									var activeBindings = itfData.bindings;
									var classField = findFieldDef(cls, itfField.name);
									if (classField == null) {
										throw 'Class ${cls.name} does not implement field ${itfField.name} required by interface ${itf.name} at ${pos.line}:${pos.col}';
									}
									if (!classField.isPublic) {
										throw 'Field ${cls.name}.${itfField.name} must be public to implement interface ${itf.name} at ${pos.line}:${pos.col}';
									}
									if (itfField.property != null) {
										if (classField.property == null) {
											throw 'Field ${cls.name}.${itfField.name} must be a property to implement interface ${itf.name} at ${pos.line}:${pos.col}';
										}
										if (classField.property.get != itfField.property.get
											|| classField.property.set != itfField.property.set) {
											throw 'Property accessors mismatch for field ${cls.name}.${itfField.name}: expected (${itfField.property.get}, ${itfField.property.set}) but got (${classField.property.get}, ${classField.property.set}) at ${pos.line}:${pos.col}';
										}
									} else {
										if (classField.property != null) {
											throw 'Field ${cls.name}.${itfField.name} cannot be a property because it is a normal variable in interface ${itf.name} at ${pos.line}:${pos.col}';
										}
									}
									if (itfField.type != null && classField.type != null) {
										var resolvedItfFieldType = resolveGenericType(itfField.type, activeBindings, scope);
										if (Std.string(resolvedItfFieldType) != Std.string(classField.type)) {
											throw 'Field ${cls.name}.${itfField.name} type mismatch: expected ${resolvedItfFieldType} but got ${classField.type} at ${pos.line}:${pos.col}';
										}
									}
								}

								for (itfKey in allItfMethods.keys()) {
									var itfData = allItfMethods.get(itfKey);
									var itfMethod = itfData.method;
									var activeBindings = itfData.bindings;
									var classMethod = findMethod(cls, itfMethod.name);
									if (classMethod == null) {
										if (itfMethod.body != null) {
											classMethod = {
												name: itfMethod.name,
												args: itfMethod.args,
												retType: itfMethod.retType,
												body: itfMethod.body,
												isStatic: false,
												isPublic: true,
												meta: itfMethod.meta
											};
											cls.methods.set(itfMethod.name, classMethod);
										} else {
											throw 'Class ${cls.name} does not implement method ${itfMethod.name} required by interface ${itf.name} at ${pos.line}:${pos.col}';
										}
									}
									if (!classMethod.isPublic) {
										throw 'Method ${cls.name}.${itfMethod.name} must be public to implement interface ${itf.name} at ${pos.line}:${pos.col}';
									}
									if (classMethod.args.length != itfMethod.args.length) {
										throw 'Method ${cls.name}.${itfMethod.name} has argument count mismatch: expected ${itfMethod.args.length} but got ${classMethod.args.length} at ${pos.line}:${pos.col}';
									}
									for (i in 0...itfMethod.args.length) {
										var itfArg = itfMethod.args[i];
										var clsArg = classMethod.args[i];
										if (itfArg.type != null && clsArg.type != null) {
											var resolvedItfArgType = resolveGenericType(itfArg.type, activeBindings, scope);
											if (Std.string(resolvedItfArgType) != Std.string(clsArg.type)) {
												throw 'Method ${cls.name}.${itfMethod.name} argument ${clsArg.name} type mismatch: expected ${resolvedItfArgType} but got ${clsArg.type} at ${pos.line}:${pos.col}';
											}
										}
									}
									if (itfMethod.retType != null && classMethod.retType != null) {
										var resolvedItfRetType = resolveGenericType(itfMethod.retType, activeBindings, scope);
										if (Std.string(resolvedItfRetType) != Std.string(classMethod.retType)) {
											throw 'Method ${cls.name}.${itfMethod.name} return type mismatch: expected ${resolvedItfRetType} but got ${classMethod.retType} at ${pos.line}:${pos.col}';
										}
									}
								}
							default:
								throw 'Invalid interface type declaration in implements list at ${pos.line}:${pos.col}';
						}
					}
				}

				scope.declare(name, cls);
				if (globals != scope) {
					globals.declare(name, cls);
				}
				if (currentPackage.length > 0) {
					registerFullyQualified(fqName, cls, globals);
				}
				return cls;

			case EInterface(name, fields, methods, parents, params, meta):
				var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
				var itf = new HaxiomInterface(name, parents);
				itf.name = fqName;
				itf.params = params != null ? params : [];
				itf.meta = evaluateMetadata(meta, scope);
				for (f in fields) {
					itf.fields.set(f.name, {
						name: f.name,
						type: f.type,
						property: f.property,
						meta: evaluateMetadata(f.meta, scope)
					});
				}
				for (m in methods) {
					itf.methods.set(m.name, {
						name: m.name,
						args: m.args,
						retType: m.retType,
						body: m.body,
						meta: evaluateMetadata(m.meta, scope)
					});
				}
				scope.declare(name, itf);
				if (globals != scope) {
					globals.declare(name, itf);
				}
				if (currentPackage.length > 0) {
					registerFullyQualified(fqName, itf, globals);
				}
				return itf;

			case EAbstract(name, underlyingType, fields, methods, params, meta):
				var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
				var abs = new HaxiomAbstract(name, underlyingType);
				abs.name = fqName;
				abs.params = params != null ? params : [];
				abs.meta = evaluateMetadata(meta, scope);
				if (abs.meta != null) {
					for (m in abs.meta) {
						if (m.name == ":haxiom.fromType" && m.params != null && m.params.length > 0) {
							abs.fromTypes.push(m.params[0]);
						} else if (m.name == ":haxiom.toType" && m.params != null && m.params.length > 0) {
							abs.toTypes.push(m.params[0]);
						}
					}
				}
				for (f in fields) {
					abs.fields.set(f.name, {
						name: f.name,
						type: f.type,
						expr: f.expr,
						isStatic: f.isStatic,
						isPublic: f.isPublic,
						isFinal: f.isFinal,
						property: f.property,
						meta: evaluateMetadata(f.meta, scope)
					});
					if (f.isStatic && f.expr != null) {
						abs.staticFields.set(f.name, eval(f.expr, scope));
					}
				}
				for (m in methods) {
					var mDyn:Dynamic = m;
					abs.methods.set(m.name, {
						name: m.name,
						args: m.args,
						retType: m.retType,
						body: m.body,
						isStatic: m.isStatic,
						isPublic: m.isPublic,
						bytecodeChunk: mDyn.bytecodeChunk,
						meta: evaluateMetadata(m.meta, scope)
					});
				}
				scope.declare(name, abs);
				if (globals != scope) {
					globals.declare(name, abs);
				}
				if (currentPackage.length > 0) {
					registerFullyQualified(fqName, abs, globals);
				}
				return abs;

			case EEnum(name, constructors, params):
				var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
				var haxiomEnum = new HaxiomEnum(name);
				haxiomEnum.name = fqName;
				if (params != null) {
					haxiomEnum.params = params;
				}
				for (c in constructors) {
					haxiomEnum.constructors.set(c.name, c.args != null ? c.args : []);
				}
				scope.declare(name, haxiomEnum);
				if (globals != scope) {
					globals.declare(name, haxiomEnum);
				}
				if (currentPackage.length > 0) {
					registerFullyQualified(fqName, haxiomEnum, globals);
				}

				// Register constructors as builders or constants
				for (c in constructors) {
					if (c.args == null) {
						var instance = new HaxiomEnumInstance(haxiomEnum, c.name, []);
						scope.declare(c.name, instance);
						if (globals != scope) {
							globals.declare(c.name, instance);
						}
					} else {
						var numArgs = c.args.length;
						var builderFunc:Dynamic = switch (numArgs) {
							case 0: () -> new HaxiomEnumInstance(haxiomEnum, c.name, []);
							case 1: (a) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a]);
							case 2: (a, b) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b]);
							case 3: (a, b, c) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b, c]);
							case 4: (a, b, c, d) -> new HaxiomEnumInstance(haxiomEnum, c.name, [a, b, c, d]);
							default: Reflect.makeVarArgs((callArgs:Array<Dynamic>) -> new HaxiomEnumInstance(haxiomEnum, c.name, callArgs));
						};
						scope.declare(c.name, builderFunc);
						if (globals != scope) {
							globals.declare(c.name, builderFunc);
						}
					}
				}
				return haxiomEnum;

			case ETypedef(name, type, params):
				var fqName = currentPackage.length > 0 ? currentPackage.join(".") + "." + name : name;
				var tdef = new HaxiomTypedef(name, type, params);
				scope.declare(name, tdef);
				if (globals != scope) {
					globals.declare(name, tdef);
				}
				if (currentPackage.length > 0) {
					registerFullyQualified(fqName, tdef, globals);
				}
				return tdef;

			case EPackage(path):
				currentPackage = path;
				return null;

			case EImport(path, alias):
				var fqName = path.join(".");
				var shortName = alias != null ? alias : path[path.length - 1];
				var targetName = path[path.length - 1];
				/*
					haxe.Log.trace("DEBUG EImport fqName: " + fqName, null);
					haxe.Log.trace("DEBUG importWhitelist: " + importWhitelist, null);
					haxe.Log.trace("DEBUG Type.resolveClass: " + Type.resolveClass(fqName), null);
					haxe.Log.trace("DEBUG isImportWhitelisted: " + isImportWhitelisted(fqName), null);
					haxe.Log.trace("DEBUG resolveNativeClass: " + resolveNativeClass(fqName), null);
				 */

				if (shortName == "*") {
					var parentPath = path.slice(0, path.length - 1).join(".");
					var prefix = parentPath + ".";

					// 1. Scan FFI exposed abstracts
					for (fqName in this.ffi.exposedAbstracts.keys()) {
						if (StringTools.startsWith(fqName, prefix) && isImportWhitelisted(fqName)) {
							var absInfo = this.ffi.exposedAbstracts.get(fqName);
							var implCls = resolveAbstractImpl(fqName, absInfo.implClass);
							if (implCls != null) {
								var parts = fqName.split(".");
								var clsShort = parts[parts.length - 1];
								scope.declare(clsShort, implCls);
							}
						}
					}

					// 2. Scan Host importWhitelist
					if (importWhitelist != null) {
						for (pattern in importWhitelist) {
							if (StringTools.startsWith(pattern, prefix)) {
								var parts = pattern.split(".");
								var clsShort = parts[parts.length - 1];
								var nativeClass = resolveNativeClass(pattern);
								if (nativeClass != null) {
									scope.declare(clsShort, nativeClass);
									continue;
								}
								var nativeEnum = Type.resolveEnum(pattern);
								if (nativeEnum != null) {
									scope.declare(clsShort, nativeEnum);
									continue;
								}
							}
						}
					}

					// 3. Scan autoWhitelistedTypes
					isAutoWhitelisted(""); // Ensure autoWhitelistedTypes is initialized
					if (autoWhitelistedTypes != null) {
						for (fq in autoWhitelistedTypes.keys()) {
							if (StringTools.startsWith(fq, prefix) && isImportWhitelisted(fq)) {
								var parts = fq.split(".");
								var clsShort = parts[parts.length - 1];
								var nativeClass = resolveNativeClass(fq);
								if (nativeClass != null) {
									scope.declare(clsShort, nativeClass);
									continue;
								}
								var nativeEnum = Type.resolveEnum(fq);
								if (nativeEnum != null) {
									scope.declare(clsShort, nativeEnum);
									continue;
								}
							}
						}
					}

					// 4. Scan StdlibRegistry
					var registryCls = Type.resolveClass("haxiom.macro.StdlibRegistry");
					if (registryCls != null) {
						var classes:Map<String, Dynamic> = Reflect.field(registryCls, "classes");
						if (classes != null) {
							for (fq in classes.keys()) {
								if (StringTools.startsWith(fq, prefix) && isImportWhitelisted(fq)) {
									var parts = fq.split(".");
									var clsShort = parts[parts.length - 1];
									scope.declare(clsShort, classes.get(fq));
								}
							}
						}
					}

					// 5. Standard Haxe core packages check (e.g. haxe.ds.*, haxe.io.*)
					var commonStdClasses = [
						"haxe.ds.StringMap", "haxe.ds.IntMap", "haxe.ds.ObjectMap", "haxe.ds.Vector", "haxe.ds.List",
						"haxe.ds.EnumValueMap", "haxe.ds.Option", "haxe.ds.Either", "haxe.io.Bytes", "haxe.io.BytesOutput",
						"haxe.io.BytesInput", "haxe.io.Path"
					];
					for (fq in commonStdClasses) {
						if (StringTools.startsWith(fq, prefix) && isImportWhitelisted(fq)) {
							var parts = fq.split(".");
							var clsShort = parts[parts.length - 1];
							var nativeClass = resolveNativeClass(fq);
							if (nativeClass != null) {
								scope.declare(clsShort, nativeClass);
							}
						}
					}

					// 6. Module resolver
					if (moduleResolver != null) {
						var moduleScope = getOrLoadModule(parentPath);
						if (moduleScope != null) {
							for (key in moduleScope.variables.keys()) {
								scope.declare(key, moduleScope.variables.get(key));
							}
						}
					}

					// 7. Check local package namespaces in globals/scope
					var parts = parentPath.split(".");
					var currentObj:Dynamic = null;
					if (scope.exists(parts[0])) {
						currentObj = scope.get(parts[0]);
						for (i in 1...parts.length) {
							if (currentObj != null && safeHasField(currentObj, parts[i])) {
								currentObj = safeField(currentObj, parts[i]);
							} else {
								currentObj = null;
								break;
							}
						}
					}
					if (currentObj != null) {
						for (field in safeFields(currentObj)) {
							if (field != "__isHaxiomPackage") {
								scope.declare(field, safeField(currentObj, field));
							}
						}
					}
					return null;
				}

				// Check if the FQ name resolves to a Haxiom-defined class/interface/enum/abstract in the globals/scope package namespaces
				var parts = path;
				var currentObj:Dynamic = null;
				if (scope.exists(parts[0])) {
					currentObj = scope.get(parts[0]);
					for (i in 1...parts.length) {
						if (currentObj != null && safeHasField(currentObj, parts[i])) {
							currentObj = safeField(currentObj, parts[i]);
						} else {
							currentObj = null;
							break;
						}
					}
				}
				if (currentObj != null) {
					scope.declare(shortName, currentObj);
					return null;
				}

				if (isImportWhitelisted(fqName)) {
					if (this.ffi.exposedAbstracts.exists(fqName)) {
						var absInfo = this.ffi.exposedAbstracts.get(fqName);
						var implCls = resolveAbstractImpl(fqName, absInfo.implClass);
						if (implCls != null) {
							scope.declare(shortName, implCls);
							return null;
						}
					}
					var nativeClass = resolveNativeClass(fqName);
					if (nativeClass != null) {
						scope.declare(shortName, nativeClass);
						return null;
					}
					var nativeEnum = Type.resolveEnum(fqName);
					if (nativeEnum != null) {
						scope.declare(shortName, nativeEnum);
						return null;
					}

					// Module check
					if (this.ffi.exposedModules.exists(fqName)) {
						var types = this.ffi.exposedModules.get(fqName);
						for (typeFq in types) {
							var subParts = typeFq.split(".");
							var subShortName = subParts[subParts.length - 1];
							var nc = resolveNativeClass(typeFq);
							if (nc != null) {
								scope.declare(subShortName, nc);
							} else {
								var ne = Type.resolveEnum(typeFq);
								if (ne != null) {
									scope.declare(subShortName, ne);
								}
							}
						}
						return null;
					}

					// Module subtype check
					for (modKey in this.ffi.exposedModules.keys()) {
						if (StringTools.startsWith(fqName, modKey + ".")) {
							var subName = fqName.substr(modKey.length + 1);
							var lastDot = modKey.lastIndexOf(".");
							var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
							var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;

							var nc = resolveNativeClass(runtimeFq);
							if (nc != null) {
								scope.declare(shortName, nc);
								return null;
							}
							var ne = Type.resolveEnum(runtimeFq);
							if (ne != null) {
								scope.declare(shortName, ne);
								return null;
							}
						}
					}
				}

				if (moduleResolver != null) {
					var moduleScope = getOrLoadModule(fqName);
					if (moduleScope != null) {
						if (moduleScope.variables.exists(targetName)) {
							scope.declare(shortName, moduleScope.variables.get(targetName));
							return null;
						} else {
							for (key in moduleScope.variables.keys()) {
								if (key == targetName || StringTools.endsWith(key, "." + targetName)) {
									scope.declare(shortName, moduleScope.variables.get(key));
									return null;
								}
							}
						}
					}
				}

				throw 'Could not resolve import $fqName';

			case EUsing(path):
				var fqName = path.join(".");
				if (!isImportWhitelisted(fqName)) {
					throw 'Using $fqName is not whitelisted';
				}
				var resolved = resolveTypePath(path, scope);
				if (resolved == null) {
					throw 'Could not resolve using target: $fqName';
				}
				if (activeUsings.indexOf(resolved) == -1) {
					activeUsings.push(resolved);
				}
				return null;

			case EThrow(expr):
				var val = eval(expr, scope);
				throw val;

			case ETry(tryExpr, catches):
				var stackDepth = callStack.length;
				try {
					return eval(tryExpr, scope);
				} catch (flow:ControlFlow) {
					throw flow;
				} catch (errVal:Dynamic) {
					while (callStack.length > stackDepth) {
						callStack.pop();
					}
					for (c in catches) {
						var caseScope = Scope.create(scope);
						var matched = false;
						try {
							if (matchPattern(errVal, c.pattern, scope, caseScope)) {
								var typeMatched = true;
								if (c.type != null) {
									try {
										errVal = castOrCheckType(errVal, c.type, scope);
										switch (c.pattern.def) {
											case EIdent(name):
												caseScope.set(name, errVal);
											default:
										}
									} catch (_:Dynamic) {
										typeMatched = false;
									}
								}
								if (typeMatched) {
									var guardMatched = true;
									if (c.guard != null) {
										guardMatched = eval(c.guard, caseScope) == true;
									}
									if (guardMatched) {
										matched = true;
										var result = eval(c.body, caseScope);
										Scope.recycle(caseScope);
										return result;
									}
								}
							}
						} catch (ex:Dynamic) {
							Scope.recycle(caseScope);
							throw ex;
						}
						Scope.recycle(caseScope);
					}
					throw errVal;
				}

			case EMeta(meta, expr):
				return eval(expr, scope);

			case ECast(expr, type):
				var val = eval(expr, scope);
				if (type != null) {
					try {
						val = castOrCheckType(val, type, scope);
					} catch (err:Dynamic) {
						throw 'Class cast error: expected ${typeToString(type)} but got ${val}';
					}
				}
				return val;

			case EBlock(exprs):
				var bScope = (scope == globals) ? globals : Scope.create(scope);
				var lastVal:Dynamic = null;
				try {
					for (expr in exprs) {
						lastVal = eval(expr, bScope);
					}
					if (bScope != globals) {
						Scope.recycle(bScope);
					}
				} catch (ex:Dynamic) {
					if (bScope != globals) {
						Scope.recycle(bScope);
					}
					throw ex;
				}
				return lastVal;

			case EFunction(name, args, retType, body):
				var closure = Scope.create(scope);
				closure.markCaptured();
				var func = (callArgs:Array<Dynamic>) -> {
					#if haxiom_debug
					trace('Interp guest function invoked! callArgs=' + callArgs);
					#end
					var fScope = Scope.create(closure);
					for (i in 0...args.length) {
						var arg = args[i];
						var val:Dynamic = null;
						if (arg.isRest) {
							val = callArgs.slice(i);
							if (arg.type != null) {
								var arr:Array<Dynamic> = cast val;
								for (j in 0...arr.length) {
									arr[j] = castOrCheckType(arr[j], arg.type, fScope);
								}
							}
						} else {
							val = i < callArgs.length ? callArgs[i] : null;
							val = castOrCheckType(val, arg.type, fScope);
						}
						fScope.declare(arg.name, val, arg.type);
					}
					var funcName = name != null ? name : "anonymous";
					pushFrame(funcName, body != null ? body.pos : {line: 1, col: 1});
					try {
						var res = eval(body, fScope);
						if (retType != null && typeToString(retType) == "Void") {
							res = null;
						} else {
							res = castOrCheckType(res, retType, fScope);
						}
						popFrame();
						Scope.recycle(fScope);
						return res;
					} catch (flow:ControlFlow) {
						popFrame();
						switch (flow) {
							case Return(val):
								if (retType != null && typeToString(retType) == "Void") {
									Scope.recycle(fScope);
									return null;
								}
								try {
									val = castOrCheckType(val, retType, fScope);
								} catch (e:Dynamic) {
									Scope.recycle(fScope);
									throw e;
								}
								Scope.recycle(fScope);
								return val;
							default:
								Scope.recycle(fScope);
								throw flow;
						}
					} catch (err:Dynamic) {
						popFrame();
						Scope.recycle(fScope);
						throw err;
					}
				};
				var hasRest = false;
				for (a in args) {
					if (a.isRest) {
						hasRest = true;
						break;
					}
				}
				var haxeFunc:Dynamic = null;
				if (hasRest) {
					haxeFunc = Reflect.makeVarArgs(func);
				} else {
					haxeFunc = switch (args.length) {
						case 0: () -> func([]);
						case 1: (a) -> func([a]);
						case 2: (a, b) -> func([a, b]);
						case 3: (a, b, c) -> func([a, b, c]);
						case 4: (a, b, c, d) -> func([a, b, c, d]);
						default: Reflect.makeVarArgs(func);
					};
				}
				var signatureArgs = [];
				for (arg in args) {
					var t = arg.type != null ? arg.type : TPath(["Dynamic"], []);
					var currentBindings:Map<String, TypeDecl> = null;
					if (scope.exists("this")) {
						var thisVal = scope.get("this");
						if (thisVal != null && Std.isOfType(thisVal, HaxiomInstance)) {
							currentBindings = (cast thisVal : HaxiomInstance).genericBindings;
						}
					}
					var resolvedT = resolveGenericType(t, currentBindings, scope);
					signatureArgs.push(resolvedT);
				}
				var signatureRet = retType != null ? retType : TPath(["Dynamic"], []);
				var currentBindings:Map<String, TypeDecl> = null;
				if (scope.exists("this")) {
					var thisVal = scope.get("this");
					if (thisVal != null && Std.isOfType(thisVal, HaxiomInstance)) {
						currentBindings = (cast thisVal : HaxiomInstance).genericBindings;
					}
				}
				var resolvedRet = resolveGenericType(signatureRet, currentBindings, scope);
				functionSignatures.set(haxeFunc, TFun(signatureArgs, resolvedRet));
				if (name != null) {
					scope.declare(name, haxeFunc);
				}
				return haxeFunc;

			case EIf(cond, e1, e2):
				var v = eval(cond, scope);
				if (isTruthy(v)) {
					return eval(e1, scope);
				} else if (e2 != null) {
					return eval(e2, scope);
				}
				return null;

			case EWhile(cond, body):
				var lastVal:Dynamic = null;
				while (true) {
					var c = eval(cond, scope);
					if (!isTruthy(c))
						break;
					try {
						lastVal = eval(body, scope);
					} catch (flow:ControlFlow) {
						switch (flow) {
							case Break: return lastVal;
							case Continue: continue;
							case Return(val): throw Return(val);
						}
					}
				}
				return lastVal;

			case EDoWhile(cond, body):
				var lastVal:Dynamic = null;
				while (true) {
					try {
						lastVal = eval(body, scope);
					} catch (flow:ControlFlow) {
						switch (flow) {
							case Break: return lastVal;
							case Continue: // Fall through to condition check
							case Return(val): throw Return(val);
						}
					}
					var c = eval(cond, scope);
					if (!isTruthy(c))
						break;
				}
				return lastVal;

			case EFor(vName, iterableExpr, body):
				var iterable = eval(iterableExpr, scope);
				var lastVal:Dynamic = null;

				// Dynamic Haxe Iterator protocol
				if (iterable != null) {
					var iterator:Dynamic = null;
					if (Std.isOfType(iterable, Array)) {
						iterator = (cast iterable : Array<Dynamic>).iterator();
					} else if (Std.isOfType(iterable, haxe.Constraints.IMap)) {
						iterator = (cast iterable : haxe.Constraints.IMap<Dynamic, Dynamic>).iterator();
					} else if (Std.isOfType(iterable, IntIterator)) {
						iterator = iterable;
					} else {
						var iterField = safeField(iterable, "iterator");
						if (iterField != null) {
							iterator = Reflect.callMethod(iterable, iterField, []);
						} else if (safeField(iterable, "hasNext") != null && safeField(iterable, "next") != null) {
							iterator = iterable;
						}
					}

					if (iterator != null) {
						if (Std.isOfType(iterator, IntIterator)) {
							var it:IntIterator = cast iterator;
							while (it.hasNext()) {
								var item = it.next();
								var fScope = Scope.create(scope);
								fScope.declare(vName, item);
								try {
									lastVal = eval(body, fScope);
									Scope.recycle(fScope);
								} catch (flow:ControlFlow) {
									Scope.recycle(fScope);
									switch (flow) {
										case Break: break;
										case Continue: continue;
										case Return(val): throw Return(val);
									}
								} catch (err:Dynamic) {
									Scope.recycle(fScope);
									throw err;
								}
							}
						} else if (safeField(iterator, "hasNext") != null && safeField(iterator, "next") != null) {
							var hasNextFn = safeField(iterator, "hasNext");
							var nextFn = safeField(iterator, "next");
							while (Reflect.callMethod(iterator, hasNextFn, [])) {
								var item = Reflect.callMethod(iterator, nextFn, []);
								var fScope = Scope.create(scope);
								fScope.declare(vName, item);
								try {
									lastVal = eval(body, fScope);
									Scope.recycle(fScope);
								} catch (flow:ControlFlow) {
									Scope.recycle(fScope);
									switch (flow) {
										case Break: break;
										case Continue: continue;
										case Return(val): throw Return(val);
									}
								} catch (err:Dynamic) {
									Scope.recycle(fScope);
									throw err;
								}
							}
						}
					}
				}
				return lastVal;

			case ESwitch(expr, cases, defExpr):
				var val = eval(expr, scope);
				var matched = false;
				var result:Dynamic = null;
				for (c in cases) {
					for (vExpr in c.values) {
						var caseScope = Scope.create(scope);
						try {
							if (matchPattern(val, vExpr, scope, caseScope)) {
								var guardOk = true;
								if (c.guard != null) {
									var guardVal = eval(c.guard, caseScope);
									if (guardVal != true) {
										guardOk = false;
									}
								}
								if (guardOk) {
									matched = true;
									result = eval(c.expr, caseScope);
									Scope.recycle(caseScope);
									break;
								}
							}
							Scope.recycle(caseScope);
						} catch (ex:Dynamic) {
							Scope.recycle(caseScope);
							throw ex;
						}
					}
					if (matched)
						break;
				}
				if (!matched && defExpr != null) {
					result = eval(defExpr, scope);
				}
				return result;

			case EReturn(retExpr):
				var val = retExpr != null ? eval(retExpr, scope) : null;
				throw Return(val);

			case EBreak:
				throw Break;

			case EContinue:
				throw Continue;
		}
		return null;
	}

	function assign(target:Expr, val:Dynamic, scope:Scope) {
		switch (target.def) {
			case EIdent(name):
				if (scope.exists(name)) {
					scope.checkAndSet(name, val, this);
				} else if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
					var inst:HaxiomInstance = cast currentThis;
					var fDef = findFieldDef(inst.cls, name);
					if (fDef != null && fDef.property != null && fDef.property.set == "set" && !isInsideAccessor(name)) {
						var m = findMethod(inst.cls, "set_" + name);
						if (m != null) {
							Reflect.callMethod(null, bindMethod(currentThis, m), [val]);
							return;
						}
					}
					if (fDef != null && fDef.isFinal) {
						if (currentConstructorInstance != inst) {
							throw 'Cannot reassign final field $name outside of constructor';
						}
					}
					if (fDef != null && fDef.type != null) {
						checkType(val, fDef.type, scope, inst.genericBindings);
					}
					inst.fields.set(name, val);
				} else {
					scope.checkAndSet(name, val, this);
				}
			case EField(objExpr, field):
				switch (objExpr.def) {
					case EIdent("super"):
						if (currentThis != null && Std.isOfType(currentThis, HaxiomInstance)) {
							var inst:HaxiomInstance = cast currentThis;
							inst.fields.set(field, val);
							return;
						}
						throw "Cannot use 'super' outside of a class instance";
					default:
				}
				var obj = eval(objExpr, scope);
				if (Std.isOfType(obj, HaxiomInstance)) {
					var inst:HaxiomInstance = cast obj;
					var fDef = findFieldDef(inst.cls, field);
					if (fDef != null && fDef.property != null && fDef.property.set == "set" && !isInsideAccessor(field)) {
						var m = findMethod(inst.cls, "set_" + field);
						if (m != null) {
							Reflect.callMethod(null, bindMethod(obj, m), [val]);
							return;
						}
					}
					if (fDef != null && fDef.isFinal) {
						if (currentConstructorInstance != inst) {
							throw 'Cannot reassign final field $field outside of constructor';
						}
					}
					if (fDef != null && fDef.type != null) {
						checkType(val, fDef.type, scope, inst.genericBindings);
					}
					inst.fields.set(field, val);
				} else {
					if (Std.isOfType(obj, HaxiomClass)) {
						var cls:HaxiomClass = cast obj;
						var fDef = findFieldDef(cls, field);
						if (fDef != null && fDef.isFinal) {
							throw 'Cannot reassign static final field $field';
						}
						if (fDef != null && fDef.type != null) {
							checkType(val, fDef.type, scope);
						}
						cls.staticFields.set(field, val);
					} else {
						Reflect.setField(obj, field, val);
					}
				}
			default:
				throw "Invalid assignment target";
		}
	}

	function isSubclassOf(c1:HaxiomClass, c2:HaxiomClass):Bool {
		var curr = c1;
		while (curr != null) {
			if (curr == c2)
				return true;
			curr = curr.parent;
		}
		return false;
	}

	function isContextInsideClass(targetCls:HaxiomClass):Bool {
		if (currentThis != null) {
			if (Std.isOfType(currentThis, HaxiomInstance)) {
				var inst:HaxiomInstance = cast currentThis;
				if (isSubclassOf(inst.cls, targetCls) || isSubclassOf(targetCls, inst.cls)) {
					return true;
				}
			} else if (Std.isOfType(currentThis, HaxiomClass)) {
				var cls:HaxiomClass = cast currentThis;
				if (isSubclassOf(cls, targetCls) || isSubclassOf(targetCls, cls)) {
					return true;
				}
			}
		}
		return false;
	}

	function isInsideAccessor(fieldName:String):Bool {
		// haxe.Log.trace("isInsideAccessor check for " + fieldName + ", stack: " + [for (f in callStack) f.method].join(", "), null);
		if (callStack.length == 0)
			return false;
		var suffix1 = ".get_" + fieldName;
		var suffix2 = ".set_" + fieldName;
		var i = callStack.length - 1;
		while (i >= 0) {
			var method = callStack[i].method;
			if (StringTools.endsWith(method, suffix1)
				|| StringTools.endsWith(method, suffix2)
				|| method == "get_" + fieldName
				|| method == "set_" + fieldName) {
				return true;
			}
			i--;
		}
		return false;
	}

	function getMetaPath(v:Dynamic):Null<String> {
		if (v == null)
			return null;
		if (Std.isOfType(v, String)) {
			return v;
		}
		if (Std.isOfType(v, HaxiomClass)) {
			return (cast v:HaxiomClass).name;
		}
		if (Reflect.hasField(v, "def")) {
			var exprPath = extractPath(cast v);
			if (exprPath != null) {
				return exprPath.join(".");
			}
		}
		return null;
	}

	function checkPrivateAccessBypass(metaList:Array<{name:String, params:Array<Dynamic>}>, targetClassName:String, fieldName:String, isAccessMode:Bool):Bool {
		if (metaList == null)
			return false;
		for (m in metaList) {
			var isBypassMeta = (isAccessMode && (m.name == ":access" || m.name == "access")) ||
			                   (!isAccessMode && (m.name == ":allow" || m.name == "allow"));
			if (isBypassMeta) {
				if (m.params != null && m.params.length > 0) {
					var pathStr = getMetaPath(m.params[0]);
					if (pathStr != null) {
						if (pathStr == targetClassName || pathStr == targetClassName + "." + fieldName) {
							return true;
						}
					}
				}
			} else if (m.name == ":noPrivateAccess" || m.name == "noPrivateAccess") {
				return true;
			}
		}
		return false;
	}

	function checkMemberAccess(targetCls:HaxiomClass, isPublic:Bool, ?pos:Pos, ?fieldName:String):Void {
		if (isPublic)
			return;
		if (pos != null && pos.file == "host")
			return;

		var activeClassName:Null<String> = null;
		var activeMethodName:Null<String> = null;
		if (callStack.length > 0) {
			var lastFrame = callStack[callStack.length - 1];
			var parts = lastFrame.method.split(".");
			if (parts.length >= 2) {
				activeMethodName = parts[parts.length - 1];
				activeClassName = parts.slice(0, parts.length - 1).join(".");
			}
		}

		if (activeClassName != null) {
			var activeCls:Dynamic = resolveTypePath(activeClassName.split("."), globals);
			if (activeCls != null && Std.isOfType(activeCls, HaxiomClass)) {
				var hCls:HaxiomClass = cast activeCls;
				if (checkPrivateAccessBypass(hCls.meta, targetCls.name, fieldName, true)) {
					return;
				}
				if (activeMethodName != null) {
					var activeM = hCls.methods.get(activeMethodName);
					if (activeM != null && checkPrivateAccessBypass(activeM.meta, targetCls.name, fieldName, true)) {
						return;
					}
				}
			}
			if (checkPrivateAccessBypass(targetCls.meta, activeClassName, activeMethodName, false)) {
				return;
			}
		}

		if (currentThis != null) {
			if (Std.isOfType(currentThis, HaxiomInstance)) {
				var inst:HaxiomInstance = cast currentThis;
				if (isSubclassOf(inst.cls, targetCls) || isSubclassOf(targetCls, inst.cls)) {
					return;
				}
			} else if (Std.isOfType(currentThis, HaxiomClass)) {
				var cls:HaxiomClass = cast currentThis;
				if (isSubclassOf(cls, targetCls) || isSubclassOf(targetCls, cls)) {
					return;
				}
			}
		}
		throw 'Cannot access private member of class ${targetCls.name}';
	}

	function extractPath(expr:Expr):Null<Array<String>> {
		switch (expr.def) {
			case EIdent(name):
				return [name];
			case EField(objExpr, field):
				var sub = extractPath(objExpr);
				if (sub != null) {
					sub.push(field);
					return sub;
				}
				return null;
			default:
				return null;
		}
	}

	function matchPattern(val:Dynamic, pattern:Expr, scope:Scope, outBindings:Scope):Bool {
		switch (pattern.def) {
			case EBinop("|", left, right):
				var tempScope = Scope.create(outBindings);
				if (matchPattern(val, left, scope, tempScope)) {
					for (k in tempScope.variables.keys()) {
						outBindings.declare(k, tempScope.variables.get(k));
					}
					Scope.recycle(tempScope);
					return true;
				}
				Scope.recycle(tempScope);

				tempScope = Scope.create(outBindings);
				if (matchPattern(val, right, scope, tempScope)) {
					for (k in tempScope.variables.keys()) {
						outBindings.declare(k, tempScope.variables.get(k));
					}
					Scope.recycle(tempScope);
					return true;
				}
				Scope.recycle(tempScope);
				return false;

			case EBinop("=>", extractor, pattern):
				var tempScope = Scope.create(scope);
				tempScope.declare("_", val);
				var extractedVal:Dynamic = null;
				try {
					extractedVal = eval(extractor, tempScope);
				} catch (e:Dynamic) {
					Scope.recycle(tempScope);
					return false;
				}
				var matched = matchPattern(extractedVal, pattern, scope, outBindings);
				Scope.recycle(tempScope);
				return matched;

			case EIdent("_"):
				return true;

			case EIdent(name):
				// Check if name is a known enum constructor for val
				if (Std.isOfType(val, HaxiomEnumInstance)) {
					var valInst:HaxiomEnumInstance = cast val;
					if (valInst.constructorName == name) {
						return true;
					}
				} else if (Reflect.isEnumValue(val)) {
					if (Type.enumConstructor(val) == name) {
						return true;
					}
				}

				if (scope.exists(name)) {
					var inScopeVal = scope.get(name);
					if (Std.isOfType(inScopeVal, HaxiomEnumInstance)) {
						var enumInst:HaxiomEnumInstance = cast inScopeVal;
						if (Std.isOfType(val, HaxiomEnumInstance)) {
							var valInst:HaxiomEnumInstance = cast val;
							return valInst.enumType == enumInst.enumType && valInst.constructorName == enumInst.constructorName;
						}
						return false;
					} else if (Reflect.isEnumValue(inScopeVal)) {
						if (Reflect.isEnumValue(val)) {
							return Type.enumEq(val, inScopeVal);
						}
						return false;
					}
				}
				outBindings.declare(name, val);
				return true;

			case ECall(calleeExpr, args):
				var constructorName = "";
				var expectedEnum:Dynamic = null;
				var path = extractPath(calleeExpr);
				if (path != null && path.length > 0) {
					constructorName = path[path.length - 1];
					if (path.length > 1) {
						var typePath = path.slice(0, path.length - 1);
						try {
							expectedEnum = resolveTypePath(typePath, scope);
						} catch (e:Dynamic) {}
					}
				}

				if (constructorName != "") {
					if (Std.isOfType(val, HaxiomEnumInstance)) {
						var valInst:HaxiomEnumInstance = cast val;
						if (valInst.constructorName == constructorName) {
							if (expectedEnum != null && valInst.enumType != expectedEnum) {
								return false;
							}
							if (args.length == valInst.args.length) {
								for (i in 0...args.length) {
									if (!matchPattern(valInst.args[i], args[i], scope, outBindings)) {
										return false;
									}
								}
								return true;
							}
						}
					} else if (Reflect.isEnumValue(val)) {
						var nativeCtor = Type.enumConstructor(val);
						var nativeParams = Type.enumParameters(val);
						if (nativeCtor == constructorName) {
							if (expectedEnum != null) {
								var valEnum = Type.getEnum(val);
								if (valEnum != expectedEnum)
									return false;
							}
							if (args.length == nativeParams.length) {
								for (i in 0...args.length) {
									if (!matchPattern(nativeParams[i], args[i], scope, outBindings)) {
										return false;
									}
								}
								return true;
							}
						}
					}
				}
				return false;

			case EArrayDecl(values):
				if (val == null)
					return false;
				if (!Std.isOfType(val, Array))
					return false;
				var arr:Array<Dynamic> = cast val;
				if (arr.length != values.length)
					return false;
				for (i in 0...values.length) {
					if (!matchPattern(arr[i], values[i], scope, outBindings)) {
						return false;
					}
				}
				return true;

			case EObjectDecl(fields):
				if (val == null)
					return false;
				for (f in fields) {
					var res = hasAndGetField(val, f.name);
					if (!res.exists)
						return false;
					if (!matchPattern(res.val, f.expr, scope, outBindings)) {
						return false;
					}
				}
				return true;

			default:
				var path = extractPath(pattern);
				if (path != null && path.length > 1) {
					var ctor = path[path.length - 1];
					var typePath = path.slice(0, path.length - 1);
					var enumVal = null;
					try {
						enumVal = resolveTypePath(typePath, scope);
					} catch (_:Dynamic) {}
					if (enumVal != null) {
						if (Std.isOfType(enumVal, HaxiomEnum)) {
							var guestEnum:HaxiomEnum = cast enumVal;
							if (Std.isOfType(val, HaxiomEnumInstance)) {
								var valInst:HaxiomEnumInstance = cast val;
								if (valInst.enumType == guestEnum && valInst.constructorName == ctor && valInst.args.length == 0) {
									return true;
								}
							}
							return false;
						} else if (Type.getEnumConstructs(enumVal) != null) {
							try {
								if (Reflect.isEnumValue(val)) {
									var valEnum = Type.getEnum(val);
									if (valEnum == enumVal && Type.enumConstructor(val) == ctor && Type.enumParameters(val).length == 0) {
										return true;
									}
								}
							} catch (_:Dynamic) {}
							return false;
						}
					}
				}

				var patVal = eval(pattern, scope);
				if (Std.isOfType(val, HaxiomEnumInstance) && Std.isOfType(patVal, HaxiomEnumInstance)) {
					var valInst:HaxiomEnumInstance = cast val;
					var patInst:HaxiomEnumInstance = cast patVal;
					if (valInst.enumType != patInst.enumType || valInst.constructorName != patInst.constructorName) {
						return false;
					}
					if (valInst.args.length != patInst.args.length)
						return false;
					for (i in 0...valInst.args.length) {
						if (valInst.args[i] != patInst.args[i])
							return false;
					}
					return true;
				} else if (Reflect.isEnumValue(val) && Reflect.isEnumValue(patVal)) {
					return Type.enumEq(val, patVal);
				}
				return val == patVal;
		}
	}

	function findMethod(cls:HaxiomClass, name:String):Dynamic {
		if (cls == null)
			return null;
		if (cls.methods.exists(name))
			return cls.methods.get(name);
		return findMethod(cls.parent, name);
	}

	function findFieldDef(cls:HaxiomClass, name:String):Dynamic {
		if (cls == null)
			return null;
		if (cls.fields.exists(name))
			return cls.fields.get(name);
		return findFieldDef(cls.parent, name);
	}

	function findStaticMethod(cls:HaxiomClass, name:String):Dynamic {
		if (cls == null)
			return null;
		if (cls.methods.exists(name)) {
			var m = cls.methods.get(name);
			if (m.isStatic)
				return m;
		}
		return findStaticMethod(cls.parent, name);
	}

	function bindMethod(obj:Dynamic, method:ClassMethodInfo):Dynamic {
		var bindings = (obj != null && Std.isOfType(obj, HaxiomInstance)) ? (cast obj : HaxiomInstance).genericBindings : null;
		var func = (callArgs:Array<Dynamic>) -> {
			var mDyn:Dynamic = method;
			if (mDyn.isAbstract) {
				throw 'Cannot call abstract method ${method.name}';
			}
			if (mDyn.isExtern == true) {
				var hostTarget:Dynamic = null;
				if (obj != null && !Std.isOfType(obj, HaxiomClass) && !Std.isOfType(obj, HaxiomInstance)) {
					hostTarget = obj;
				} else if (globals.exists(method.name)) {
					hostTarget = globals.get(method.name);
				}
				if (hostTarget != null) {
					if (Reflect.isFunction(hostTarget)) {
						return Reflect.callMethod(null, hostTarget, callArgs);
					}
					var f = Reflect.field(hostTarget, method.name);
					if (f != null && Reflect.isFunction(f)) {
						return Reflect.callMethod(hostTarget, f, callArgs);
					}
				}
				var errLine = lastEvalPos != null ? lastEvalPos.line : 1;
				var errCol = lastEvalPos != null ? lastEvalPos.col : 1;
				var errFile = lastEvalPos != null && lastEvalPos.file != null ? lastEvalPos.file : "script";
				var errMsg = 'Runtime Error: Unbound Host Extern \'${method.name}\' at ${errFile}:${errLine}:${errCol}';
				throw new haxiom.ScriptException('Unbound Host Extern \'${method.name}\'', callStack.copy(), errMsg, errLine, errCol, errFile);
			}
			#if haxiom_debug
			trace('Interp bindMethod guest function invoked! callArgs=' + callArgs);
			#end
			var fScope = Scope.create(globals);
			fScope.declare("this", obj);
			var mappedArgs = [];
			for (i in 0...method.args.length) {
				var arg = method.args[i];
				var val:Dynamic = null;
				if (arg.isRest) {
					val = callArgs.slice(i);
					if (arg.type != null) {
						var arr:Array<Dynamic> = cast val;
						for (j in 0...arr.length) {
							arr[j] = castOrCheckType(arr[j], arg.type, fScope, bindings);
						}
					}
				} else {
					val = i < callArgs.length ? callArgs[i] : null;
					val = castOrCheckType(val, arg.type, fScope, bindings);
				}
				fScope.declare(arg.name, val, arg.type);
				mappedArgs.push(val);
			}
			var oldThis = currentThis;
			currentThis = obj;
			var oldAbstract = inAbstractMethod;
			if (Std.isOfType(obj, HaxiomAbstractInstance)) {
				inAbstractMethod = true;
			}
			var className = "toplevel";
			if (obj != null) {
				if (Std.isOfType(obj, HaxiomInstance)) {
					className = (cast obj : HaxiomInstance).cls.name;
				} else if (Std.isOfType(obj, HaxiomAbstractInstance)) {
					className = (cast obj : HaxiomAbstractInstance).abstractType.name;
				} else if (Std.isOfType(obj, HaxiomClass)) {
					className = (cast obj : HaxiomClass).name;
				}
			}
			if (isNamespaceHalted(className)) {
				return null;
			}
			pushFrame(className + "." + method.name, method.body != null ? method.body.pos : {line: 1, col: 1});
			var isMethodAsync = false;
			if (method.meta != null) {
				for (m in method.meta) {
					if (m.name == ":haxiom.async") {
						isMethodAsync = true;
						break;
					}
				}
			}

			if (isMethodAsync && !useVM) {
				throw 'Async/await execution requires Haxiom VM mode (useVM = true)';
			}

			try {
				var res:Dynamic = null;
				var mDyn:Dynamic = method;
				if (useVM || (method.body == null && mDyn.bytecodeChunk != null)) {
					if (mDyn.bytecodeChunk == null && method.body != null) {
						mDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(method.body, method.args, false, isMethodAsync, debugMode, method.name);
					}
					isMethodAsync = mDyn.bytecodeChunk.isAsync;
					res = haxiom.VM.runChunk(this, mDyn.bytecodeChunk, fScope, obj, className + "." + method.name, mappedArgs);
				} else {
					res = eval(method.body, fScope);
				}
				if (method.retType != null && typeToString(method.retType) == "Void") {
					res = null;
				} else {
					if (!isMethodAsync) {
						res = castOrCheckType(res, method.retType, fScope, bindings);
					}
				}
				inAbstractMethod = oldAbstract;
				currentThis = oldThis;
				popFrame();
				if (!isMethodAsync) {
					Scope.recycle(fScope);
				}
				return res;
			} catch (flow:ControlFlow) {
				inAbstractMethod = oldAbstract;
				currentThis = oldThis;
				popFrame();
				switch (flow) {
					case Return(val):
						var finalVal = val;
						if (method.retType != null && typeToString(method.retType) == "Void") {
							if (!isMethodAsync)
								Scope.recycle(fScope);
							return null;
						}
						try {
							if (!isMethodAsync)
								finalVal = castOrCheckType(finalVal, method.retType, fScope, bindings);
						} catch (e:Dynamic) {
							if (!isMethodAsync)
								Scope.recycle(fScope);
							throw e;
						}
						if (!isMethodAsync)
							Scope.recycle(fScope);
						return finalVal;
					default:
						if (!isMethodAsync)
							Scope.recycle(fScope);
						throw flow;
				}
			} catch (e:Dynamic) {
				inAbstractMethod = oldAbstract;
				currentThis = oldThis;
				popFrame();
				if (!isMethodAsync)
					Scope.recycle(fScope);

				var se:ScriptException = null;
				if (Std.isOfType(e, ScriptException)) {
					se = cast e;
				} else {
					se = new ScriptException(e, callStack.copy(), "Runtime Error: " + Std.string(e), 1, 1, className + "." + method.name);
				}

				haltNamespace(className);

				if (onRuntimeError != null) {
					onRuntimeError(se);
					return null;
				}
				throw se;
			}
		};
		var hasRest = false;
		for (arg in method.args) {
			if (arg.isRest) {
				hasRest = true;
				break;
			}
		}
		var boundFunc:Dynamic = null;
		#if (cpp || hl || java || cs)
		boundFunc = Reflect.makeVarArgs(func);
		#else
		if (hasRest) {
			boundFunc = Reflect.makeVarArgs(func);
		} else {
			boundFunc = switch (method.args.length) {
				case 0: () -> func([]);
				case 1: (a) -> func([a]);
				case 2: (a, b) -> func([a, b]);
				case 3: (a, b, c) -> func([a, b, c]);
				case 4: (a, b, c, d) -> func([a, b, c, d]);
				default: Reflect.makeVarArgs(func);
			};
		}
		#end
		var signatureArgs = [];
		for (arg in method.args) {
			var t = arg.type != null ? arg.type : TPath(["Dynamic"], []);
			var resolvedT = resolveGenericType(t, bindings, globals);
			signatureArgs.push(resolvedT);
		}
		var signatureRet = method.retType != null ? method.retType : TPath(["Dynamic"], []);
		var resolvedRet = resolveGenericType(signatureRet, bindings, globals);
		functionSignatures.set(boundFunc, TFun(signatureArgs, resolvedRet));
		return boundFunc;
	}

	function bindStaticExtensionMethod(obj:Dynamic, method:{
		name:String,
		args:Array<FunctionArg>,
		retType:Null<TypeDecl>,
		body:Expr,
		isStatic:Bool,
		isPublic:Bool
	}):Dynamic {
		var bindings = (obj != null && Std.isOfType(obj, HaxiomInstance)) ? (cast obj : HaxiomInstance).genericBindings : null;
		var func = (callArgs:Array<Dynamic>) -> {
			var fScope = Scope.create(globals);
			var fullArgs = [obj].concat(callArgs);
			for (i in 0...method.args.length) {
				var arg = method.args[i];
				var val:Dynamic = null;
				if (arg.isRest) {
					val = fullArgs.slice(i);
					if (arg.type != null) {
						var arr:Array<Dynamic> = cast val;
						for (j in 0...arr.length) {
							arr[j] = castOrCheckType(arr[j], arg.type, fScope, bindings);
						}
					}
				} else {
					val = i < fullArgs.length ? fullArgs[i] : null;
					val = castOrCheckType(val, arg.type, fScope, bindings);
				}
				fScope.declare(arg.name, val, arg.type);
			}
			var oldThis = currentThis;
			currentThis = null;
			var className = (obj != null && Std.isOfType(obj, HaxiomInstance)) ? (cast(obj, HaxiomInstance).cls.name) : "static";
			pushFrame(className + "." + method.name, method.body != null ? method.body.pos : {line: 1, col: 1});
			try {
				var res:Dynamic = null;
				var mDyn:Dynamic = method;
				if (useVM || (method.body == null && mDyn.bytecodeChunk != null)) {
					if (mDyn.bytecodeChunk == null && method.body != null) {
						mDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(method.body, method.args, false, false, debugMode, method.name);
					}
					res = haxiom.VM.runChunk(this, mDyn.bytecodeChunk, fScope, null, className + "." + method.name, fullArgs);
				} else {
					res = eval(method.body, fScope);
				}
				currentThis = oldThis;
				popFrame();
				Scope.recycle(fScope);
				return res;
			} catch (flow:ControlFlow) {
				currentThis = oldThis;
				popFrame();
				switch (flow) {
					case Return(val):
						var finalVal = val;
						if (method.retType != null && typeToString(method.retType) == "Void") {
							Scope.recycle(fScope);
							return null;
						}
						try {
							finalVal = castOrCheckType(finalVal, method.retType, fScope, bindings);
						} catch (e:Dynamic) {
							Scope.recycle(fScope);
							throw e;
						}
						Scope.recycle(fScope);
						return finalVal;
					default:
						Scope.recycle(fScope);
						throw flow;
				}
			} catch (e:Dynamic) {
				currentThis = oldThis;
				popFrame();
				Scope.recycle(fScope);
				throw e;
			}
		};
		var hasRest = false;
		for (i in 1...method.args.length) {
			if (method.args[i].isRest) {
				hasRest = true;
				break;
			}
		}
		var boundFunc:Dynamic = null;
		if (hasRest) {
			boundFunc = Reflect.makeVarArgs(func);
		} else {
			var arity = method.args.length - 1;
			if (arity < 0)
				arity = 0;
			boundFunc = switch (arity) {
				case 0: () -> func([]);
				case 1: (a) -> func([a]);
				case 2: (a, b) -> func([a, b]);
				case 3: (a, b, c) -> func([a, b, c]);
				case 4: (a, b, c, d) -> func([a, b, c, d]);
				default: Reflect.makeVarArgs(func);
			};
		}
		var signatureArgs = [];
		for (i in 1...method.args.length) {
			var arg = method.args[i];
			var t = arg.type != null ? arg.type : TPath(["Dynamic"], []);
			var resolvedT = resolveGenericType(t, bindings, globals);
			signatureArgs.push(resolvedT);
		}
		var signatureRet = method.retType != null ? method.retType : TPath(["Dynamic"], []);
		var resolvedRet = resolveGenericType(signatureRet, bindings, globals);
		functionSignatures.set(boundFunc, TFun(signatureArgs, resolvedRet));
		return boundFunc;
	}

	function resolveUsing(obj:Dynamic, field:String):Dynamic {
		if (activeUsings == null || activeUsings.length == 0)
			return null;
		var i = activeUsings.length - 1;
		while (i >= 0) {
			var usingTarget = activeUsings[i];
			if (usingTarget != null) {
				if (Std.isOfType(usingTarget, HaxiomClass)) {
					var cls:HaxiomClass = cast usingTarget;
					var m = findStaticMethod(cls, field);
					if (m != null) {
						return bindStaticExtensionMethod(obj, m);
					}
				} else {
					var m = Reflect.field(usingTarget, field);
					if (m != null && Reflect.isFunction(m)) {
						return Reflect.makeVarArgs(function(args:Array<Dynamic>) {
							return Reflect.callMethod(null, m, [obj].concat(args));
						});
					}
				}
			}
			i--;
		}
		return null;
	}

	public function typesEqual(t1:TypeDecl, t2:TypeDecl):Bool {
		if (t1 == null && t2 == null)
			return true;
		if (t1 == null || t2 == null)
			return false;
		switch ([t1, t2]) {
			case [TPath(p1, params1), TPath(p2, params2)]:
				if (p1.join(".") != p2.join("."))
					return false;
				if (params1.length != params2.length)
					return false;
				for (i in 0...params1.length) {
					if (!typesEqual(params1[i], params2[i]))
						return false;
				}
				return true;
			case [TFun(args1, ret1), TFun(args2, ret2)]:
				if (args1.length != args2.length)
					return false;
				for (i in 0...args1.length) {
					if (!typesEqual(args1[i], args2[i]))
						return false;
				}
				return typesEqual(ret1, ret2);
			case [TAnonymous(fields1), TAnonymous(fields2)]:
				if (fields1.length != fields2.length)
					return false;
				var map1 = [for (f in fields1) f.name => {type: f.type, opt: f.opt}];
				for (f in fields2) {
					if (!map1.exists(f.name))
						return false;
					var m1 = map1.get(f.name);
					if (m1.opt != f.opt)
						return false;
					if (!typesEqual(m1.type, f.type))
						return false;
				}
				return true;
			default:
				return false;
		}
	}

	public function lookupBinding(paramName:String, bindings:Map<String, TypeDecl>, inst:HaxiomInstance):TypeDecl {
		if (inst != null) {
			var curr = inst.cls;
			while (curr != null) {
				var key = curr.name + "." + paramName;
				if (bindings.exists(key)) {
					return bindings.get(key);
				}
				curr = curr.parent;
			}
		}
		var suffix = "." + paramName;
		for (k in bindings.keys()) {
			if (StringTools.endsWith(k, suffix) || k == paramName) {
				return bindings.get(k);
			}
		}
		return null;
	}

	public function resolveType(t:TypeDecl, scope:Scope):TypeDecl {
		if (t == null)
			return null;
		switch (t) {
			case TPath(path, params):
				var typeName = path.join(".");
				if (scope != null && scope.exists(typeName)) {
					var cls = scope.get(typeName);
					if (Std.isOfType(cls, HaxiomTypedef)) {
						var tdef:HaxiomTypedef = cast cls;
						var nextBindings = new Map<String, TypeDecl>();
						for (i in 0...tdef.params.length) {
							var paramName = tdef.params[i].name;
							if (params != null && i < params.length) {
								nextBindings.set(paramName, resolveType(params[i], scope));
							}
						}
						var resolvedUnderlying = resolveGenericType(tdef.type, nextBindings, scope);
						return resolveType(resolvedUnderlying, scope);
					}
				}
				var resolvedParams = [];
				for (p in params) {
					resolvedParams.push(resolveType(p, scope));
				}
				return TPath(path, resolvedParams);
			case TFun(args, ret):
				var resolvedArgs = [];
				for (arg in args) {
					resolvedArgs.push(resolveType(arg, scope));
				}
				return TFun(resolvedArgs, resolveType(ret, scope));
			case TAnonymous(fields):
				var resolvedFields = [];
				for (f in fields) {
					resolvedFields.push({name: f.name, type: resolveType(f.type, scope), opt: f.opt});
				}
				return TAnonymous(resolvedFields);
		}
	}

	public function resolveGenericType(type:TypeDecl, genericBindings:Map<String, TypeDecl>, scope:Scope):TypeDecl {
		if (type == null)
			return null;

		var bindings = genericBindings;
		var inst:HaxiomInstance = null;
		if (scope != null && scope.exists("this")) {
			var thisVal = scope.get("this");
			if (thisVal != null && Std.isOfType(thisVal, HaxiomInstance)) {
				inst = cast thisVal;
				if (bindings == null) {
					bindings = inst.genericBindings;
				}
			}
		}

		switch (type) {
			case TPath(path, params):
				if (path.length == 1 && bindings != null) {
					var paramName = path[0];
					var resolved = lookupBinding(paramName, bindings, inst);
					if (resolved != null)
						return resolved;
				}
				var resolvedParams = [];
				for (p in params) {
					resolvedParams.push(resolveGenericType(p, bindings, scope));
				}
				return TPath(path, resolvedParams);
			case TFun(args, ret):
				var resolvedArgs = [];
				for (arg in args) {
					resolvedArgs.push(resolveGenericType(arg, bindings, scope));
				}
				return TFun(resolvedArgs, resolveGenericType(ret, bindings, scope));
			case TAnonymous(fields):
				var resolvedFields = [];
				for (f in fields) {
					resolvedFields.push({name: f.name, type: resolveGenericType(f.type, bindings, scope), opt: f.opt});
				}
				return TAnonymous(resolvedFields);
		}
	}

	public function resolveGenericTypeInBindings(type:TypeDecl, declaringClassName:String, bindings:Map<String, TypeDecl>):TypeDecl {
		if (type == null)
			return null;
		switch (type) {
			case TPath(path, params):
				if (path.length == 1 && bindings != null) {
					var paramName = path[0];
					var key = declaringClassName + "." + paramName;
					if (bindings.exists(key)) {
						return bindings.get(key);
					}
				}
				var resolvedParams = [];
				for (p in params) {
					resolvedParams.push(resolveGenericTypeInBindings(p, declaringClassName, bindings));
				}
				return TPath(path, resolvedParams);
			case TFun(args, ret):
				var resolvedArgs = [];
				for (arg in args) {
					resolvedArgs.push(resolveGenericTypeInBindings(arg, declaringClassName, bindings));
				}
				return TFun(resolvedArgs, resolveGenericTypeInBindings(ret, declaringClassName, bindings));
			case TAnonymous(fields):
				var resolvedFields = [];
				for (f in fields) {
					resolvedFields.push({name: f.name, type: resolveGenericTypeInBindings(f.type, declaringClassName, bindings), opt: f.opt});
				}
				return TAnonymous(resolvedFields);
		}
	}

	public function populateGenericBindings(inst:HaxiomInstance, cls:HaxiomClass, concreteParams:Array<TypeDecl>, childClassName:String = null,
			childBindings:Map<String, TypeDecl> = null, scope:Scope = null) {
		if (cls.params != null) {
			for (i in 0...cls.params.length) {
				var paramDef = cls.params[i];
				var paramName = paramDef.name;
				var boundType = (concreteParams != null && i < concreteParams.length) ? concreteParams[i] : TPath(["Dynamic"], []);
				if (childClassName != null && childBindings != null) {
					boundType = resolveGenericTypeInBindings(boundType, childClassName, childBindings);
				}
				if (paramDef.constraint != null && boundType != null) {
					var expectedConstraint = resolveGenericType(paramDef.constraint, inst.genericBindings, scope);
					if (!checkTypeCompatibility(boundType, expectedConstraint, scope)) {
						throw 'Type mismatch: type parameter ${paramName} does not satisfy constraint ${typeToString(expectedConstraint)}';
					}
				}
				inst.genericBindings.set(cls.name + "." + paramName, boundType);
			}
		}
		if (cls.parentType != null) {
			switch (cls.parentType) {
				case TPath(path, parentParams):
					var parentBaseName = path.join(".");
					var parentClsVal = scope.get(parentBaseName);
					if (parentClsVal != null && Std.isOfType(parentClsVal, HaxiomClass)) {
						var parentCls:HaxiomClass = cast parentClsVal;
						populateGenericBindings(inst, parentCls, parentParams, cls.name, inst.genericBindings, scope);
					}
				default:
			}
		}
	}

	function isInterfaceCompatible(implName:String, targetItfName:String, scope:Scope):Bool {
		if (implName == targetItfName)
			return true;
		var itfVal = scope.get(implName);
		if (itfVal != null && Std.isOfType(itfVal, HaxiomInterface)) {
			var itf:HaxiomInterface = cast itfVal;
			for (p in itf.parents) {
				switch (p) {
					case TPath(pPath, _):
						var pName = pPath.join(".");
						if (isInterfaceCompatible(pName, targetItfName, scope))
							return true;
					default:
				}
			}
		}
		return false;
	}

	public function checkTypeCompatibility(typeA:TypeDecl, typeB:TypeDecl, scope:Scope):Bool {
		if (typeA == null || typeB == null)
			return true;
		if (typesEqual(typeA, typeB))
			return true;
		switch [typeA, typeB] {
			case [TPath(pathA, _), TPath(pathB, _)]:
				var nameA = pathA.join(".");
				var nameB = pathB.join(".");
				if (nameA == nameB || nameB == "Dynamic")
					return true;
				if (scope != null && scope.exists(nameA)) {
					var clsA = scope.get(nameA);
					if (Std.isOfType(clsA, HaxiomClass)) {
						var curr:HaxiomClass = cast clsA;
						while (curr != null) {
							if (curr.name == nameB)
								return true;
							for (itf in curr.interfaces) {
								switch (itf) {
									case TPath(itfPath, _):
										if (isInterfaceCompatible(itfPath.join("."), nameB, scope))
											return true;
									default:
								}
							}
							curr = curr.parent;
						}
					}
				}
				return false;
			default:
				return true;
		}
	}

	public function checkType(val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Void {
		haxiom.TypeSystem.checkType(this, val, type, scope, genericBindings);
	}

	public function castOrCheckType(val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Dynamic {
		return haxiom.TypeSystem.castOrCheckType(this, val, type, scope, genericBindings);
	}

	function hasAndGetField(obj:Dynamic, fieldName:String):{exists:Bool, val:Dynamic} {
		if (obj == null)
			return {exists: false, val: null};
		if (Std.isOfType(obj, HaxiomInstance)) {
			var inst:HaxiomInstance = cast obj;
			if (inst.fields.exists(fieldName)) {
				return {exists: true, val: inst.fields.get(fieldName)};
			}
			var m = findMethod(inst.cls, fieldName);
			if (m != null) {
				return {exists: true, val: bindMethod(inst, m)};
			}
			var fDef = findFieldDef(inst.cls, fieldName);
			if (fDef != null) {
				var fieldVal:Dynamic = null;
				if (fDef.property != null && fDef.property.get == "get") {
					var gm = findMethod(inst.cls, "get_" + fieldName);
					if (gm != null) {
						fieldVal = Reflect.callMethod(null, bindMethod(inst, gm), []);
					}
				}
				return {exists: true, val: fieldVal};
			}
			return {exists: false, val: null};
		}

		var hasF = false;
		try {
			hasF = Reflect.isObject(obj) && Reflect.hasField(obj, fieldName);
		} catch (e:Dynamic) {}
		if (hasF) {
			return {exists: true, val: safeField(obj, fieldName)};
		}
		var prop:Dynamic = null;
		try {
			prop = Reflect.getProperty(obj, fieldName);
		} catch (e:Dynamic) {}
		if (prop != null) {
			return {exists: true, val: prop};
		}
		var f:Dynamic = null;
		try {
			f = Reflect.field(obj, fieldName);
		} catch (e:Dynamic) {}
		if (f != null) {
			return {exists: true, val: f};
		}
		return {exists: false, val: null};
	}

	// Dynamic map/array subscript helpers
	function getSubscript(obj:Dynamic, key:Dynamic):Dynamic {
		if (Std.isOfType(obj, Array)) {
			return (cast obj : Array<Dynamic>)[cast key];
		} else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
			return (cast obj : haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
		} else if (Std.isOfType(obj, HaxiomInstance)) {
			return (cast obj : HaxiomInstance).fields.get(key);
		} else {
			var cls = Type.getClass(obj);
			var clsName = cls != null ? safeGetClassName(cls) : null;
			if (clsName == "haxe.ds.Vector" || clsName == "eval.Vector") {
				var vec:haxe.ds.Vector<Dynamic> = cast obj;
				return vec[cast key];
			}
			if (Type.typeof(obj) == TUnknown) {
				try {
					var vec:haxe.ds.Vector<Dynamic> = cast obj;
					return vec[cast key];
				} catch (e:Dynamic) {}
			}
		}
		throw "Target object does not support subscript access";
	}

	function setSubscript(obj:Dynamic, key:Dynamic, val:Dynamic):Void {
		if (Std.isOfType(obj, Array)) {
			var arr:Array<Dynamic> = cast obj;
			var idx:Int = cast key;
			if (idx >= arr.length) {
				trackMemory(idx - arr.length + 1);
			}
			arr[idx] = val;
		} else if (Std.isOfType(obj, haxe.Constraints.IMap)) {
			var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast obj;
			if (!map.exists(key)) {
				trackMemory(1);
			}
			map.set(key, val);
		} else if (Std.isOfType(obj, HaxiomInstance)) {
			var inst:HaxiomInstance = cast obj;
			if (!inst.fields.exists(key)) {
				trackMemory(1);
			}
			inst.fields.set(key, val);
		} else {
			var cls = Type.getClass(obj);
			var clsName = cls != null ? safeGetClassName(cls) : null;
			if (clsName == "haxe.ds.Vector" || clsName == "eval.Vector") {
				var vec:haxe.ds.Vector<Dynamic> = cast obj;
				vec[cast key] = val;
				return;
			}
			if (Type.typeof(obj) == TUnknown) {
				try {
					var vec:haxe.ds.Vector<Dynamic> = cast obj;
					vec[cast key] = val;
					return;
				} catch (e:Dynamic) {}
			}
			throw "Target object does not support subscript assignment";
		}
	}

	function typeToString(type:TypeDecl):String {
		if (type == null)
			return "Dynamic";
		switch (type) {
			case TPath(path, params):
				var base = path.join(".");
				if (params.length > 0) {
					return base + "<" + params.map(typeToString).join(", ") + ">";
				}
				return base;
			case TFun(args, ret):
				return "(" + args.map(typeToString).join(", ") + ") -> " + typeToString(ret);
			case TAnonymous(fields):
				return "{" + fields.map(f -> (f.opt == true ? "?" : "") + f.name + ":" + typeToString(f.type)).join(", ") + "}";
		}
	}

	function getExprPath(e:Expr):Array<String> {
		if (e == null)
			return null;
		switch (e.def) {
			case EIdent(name):
				return [name];
			case EField(objExpr, field):
				var sub = getExprPath(objExpr);
				if (sub != null) {
					return sub.concat([field]);
				}
			default:
		}
		return null;
	}

	function isPackageObject(val:Dynamic):Bool {
		if (val == null)
			return false;
		return safeField(val, "__isHaxiomPackage") == true;
	}

	function isClassInScope(cls:Dynamic, scope:Scope):Bool {
		if (importWhitelist == null)
			return true;
		var curr = scope;
		while (curr != null) {
			for (v in curr.variables) {
				if (v == cls)
					return true;
			}
			curr = curr.parent;
		}
		return false;
	}

	function tryResolveExpressionPath(e:Expr, scope:Scope):{success:Bool, value:Dynamic} {
		var path = getExprPath(e);
		if (path == null || path.length == 0)
			return {success: false, value: null};

		var first = path[0];
		if (scope.exists(first)) {
			var val = scope.get(first);
			if (!isPackageObject(val)) {
				return {success: false, value: null};
			}
		}

		var len = path.length;
		while (len > 0) {
			var prefix = path.slice(0, len);
			var fqName = prefix.join(".");

			var resolvedType:Dynamic = null;
			if (this.ffi.exposedAbstracts.exists(fqName)) {
				var absInfo = this.ffi.exposedAbstracts.get(fqName);
				resolvedType = resolveAbstractImpl(fqName, absInfo.implClass);
			} else {
				var cls = resolveNativeClass(fqName);
				if (cls != null) {
					resolvedType = cls;
				} else {
					var enm = Type.resolveEnum(fqName);
					if (enm != null) {
						resolvedType = enm;
					}
				}
			}

			if (resolvedType == null) {
				for (modKey in this.ffi.exposedModules.keys()) {
					if (StringTools.startsWith(fqName, modKey + ".")) {
						var subName = fqName.substr(modKey.length + 1);
						var lastDot = modKey.lastIndexOf(".");
						var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
						var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;

						var c = resolveNativeClass(runtimeFq);
						if (c != null) {
							resolvedType = c;
							break;
						}
						var enm = Type.resolveEnum(runtimeFq);
						if (enm != null) {
							resolvedType = enm;
							break;
						}
					}
				}
			}

			if (resolvedType != null) {
				if (isManualImportRequired(fqName)) {
					if (!isClassInScope(resolvedType, scope)) {
						len--;
						continue;
					}
				}
				var remaining = path.slice(len);
				var current:Dynamic = resolvedType;
				for (field in remaining) {
					if (current == null) {
						return {success: true, value: null};
					}
					var next = safeField(current, field);
					if (current == haxe.Json && field == "stringify") {
						next = (cast function(value:Dynamic, ?replacer:Dynamic, ?space:String):String {
							checkSafeToSerialize(value);
							return haxe.Json.stringify(value, replacer, space);
						} : Dynamic);
					}
					if (current == haxe.Serializer && field == "run") {
						next = (cast function(v:Dynamic) {
							checkSafeToSerialize(v);
							return haxe.Serializer.run(v);
						} : Dynamic);
					}
					current = next;
				}
				return {success: true, value: current};
			}

			len--;
		}

		return {success: false, value: null};
	}

	function resolveTypePath(path:Array<String>, scope:Scope):Dynamic {
		var name = path[0];
		var val:Dynamic = null;
		if (scope.exists(name)) {
			val = scope.get(name);
			for (i in 1...path.length) {
				if (val == null)
					break;
				val = safeField(val, path[i]);
			}
		}

		if (val != null) {
			var fq = path.join(".");
			if (isManualImportRequired(fq)) {
				if (!isClassInScope(val, scope))
					return null;
			}
			return val;
		}

		var fqName = path.join(".");

		if (this.ffi.exposedAbstracts.exists(fqName)) {
			var absInfo = this.ffi.exposedAbstracts.get(fqName);
			var impl = resolveAbstractImpl(fqName, absInfo.implClass);
			if (impl != null && isManualImportRequired(fqName)) {
				if (!isClassInScope(impl, scope))
					return null;
			}
			return impl;
		}

		var cls = resolveNativeClass(fqName);
		if (cls != null) {
			if (isManualImportRequired(fqName)) {
				if (!isClassInScope(cls, scope))
					return null;
			}
			return cls;
		}

		var enm = Type.resolveEnum(fqName);
		if (enm != null)
			return enm;

		// Check if fqName is a module subtype compile-time path
		for (modKey in this.ffi.exposedModules.keys()) {
			if (StringTools.startsWith(fqName, modKey + ".")) {
				var subName = fqName.substr(modKey.length + 1);
				var lastDot = modKey.lastIndexOf(".");
				var parentPkg = lastDot != -1 ? modKey.substring(0, lastDot) : "";
				var runtimeFq = parentPkg != "" ? parentPkg + "." + subName : subName;

				var c = resolveNativeClass(runtimeFq);
				if (c != null) {
					if (isManualImportRequired(runtimeFq)) {
						if (!isClassInScope(c, scope))
							return null;
					}
					return c;
				}
				var e = Type.resolveEnum(runtimeFq);
				if (e != null)
					return e;
			}
		}
		return null;
	}

	public function registerFullyQualified(fullName:String, value:Dynamic, scope:Scope) {
		var parts = fullName.split(".");
		if (parts.length == 1) {
			scope.declare(parts[0], value);
			return;
		}

		var current:Dynamic = null;
		var firstPart = parts[0];
		if (scope.exists(firstPart)) {
			current = scope.get(firstPart);
		} else {
			current = {};
			Reflect.setField(current, "__isHaxiomPackage", true);
			scope.declare(firstPart, current);
		}

		for (i in 1...parts.length - 1) {
			var part = parts[i];
			if (Reflect.hasField(current, part)) {
				current = Reflect.field(current, part);
			} else {
				var nextObj = {};
				Reflect.setField(nextObj, "__isHaxiomPackage", true);
				Reflect.setField(current, part, nextObj);
				current = nextObj;
			}
		}

		Reflect.setField(current, parts[parts.length - 1], value);
	}

	static var autoWhitelistedTypes:Map<String, Bool> = null;

	function isAutoWhitelisted(fqName:String):Bool {
		if (autoWhitelistedTypes == null) {
			autoWhitelistedTypes = new Map();
			#if !macro
			// 1. Classes
			var res = haxe.Resource.getString("haxiom_exposed_classes");
			if (res != null) {
				try {
					var list:Array<String> = haxe.Json.parse(res);
					for (x in list)
						autoWhitelistedTypes.set(x, true);
				} catch (e:Dynamic) {}
			}
			// 2. Abstracts
			var absRes = haxe.Resource.getString("haxiom_exposed_abstracts");
			if (absRes != null) {
				try {
					var obj:Dynamic = haxe.Json.parse(absRes);
					for (k in Reflect.fields(obj)) {
						autoWhitelistedTypes.set(k, true);
						var absInfo = Reflect.field(obj, k);
						if (absInfo != null && absInfo.implClass != null) {
							autoWhitelistedTypes.set(absInfo.implClass, true);
						}
					}
				} catch (e:Dynamic) {}
			}
			// 3. Generics
			var genRes = haxe.Resource.getString("haxiom_exposed_generics");
			if (genRes != null) {
				try {
					var obj:Dynamic = haxe.Json.parse(genRes);
					for (k in Reflect.fields(obj)) {
						var clsName = Reflect.field(obj, k);
						if (clsName != null)
							autoWhitelistedTypes.set(clsName, true);
					}
				} catch (e:Dynamic) {}
			}
			// 4. Modules
			var modRes = haxe.Resource.getString("haxiom_exposed_modules");
			if (modRes != null) {
				try {
					var obj:Dynamic = haxe.Json.parse(modRes);
					for (k in Reflect.fields(obj)) {
						autoWhitelistedTypes.set(k, true);
						var types:Array<String> = Reflect.field(obj, k);
						for (t in types)
							autoWhitelistedTypes.set(t, true);
					}
				} catch (e:Dynamic) {}
			}
			// haxe.Log.trace("DEBUG autoWhitelistedKeys: " + [for (k in autoWhitelistedTypes.keys()) k], null);
			#end
		}
		return autoWhitelistedTypes.exists(fqName);
	}

	function isManualImportRequired(fqName:String):Bool {
		if (fqName.indexOf(".") != -1) {
			return false;
		}
		if (fqName == "Math" || fqName == "Std" || fqName == "Reflect" || fqName == "Type" || fqName == "Lambda") {
			return false;
		}
		var isGlobalPrimitive = (fqName == "String" || fqName == "Array" || fqName == "Int" || fqName == "Float" || fqName == "Bool" || fqName == "Dynamic"
			|| fqName == "Class" || fqName == "Enum" || fqName == "EReg");
		if (isGlobalPrimitive) {
			return false;
		}
		if (fqName == "Date" || fqName == "DateTools" || fqName == "StringBuf" || fqName == "Xml" || fqName == "StringTools") {
			return true;
		}
		if (StringTools.startsWith(fqName, "haxe.")) {
			return true;
		}
		return false;
	}

	function throwSecurityErrorForUnwhitelistedClass(field:String, name:String):Void {
		var parts = name.split(".");
		var hint = parts.length > 1 ? 'haxiom.exposePackage("${parts[0]}.*") or haxiom.exposeClass("$name", $name)' : 'haxiom.exposeClass("$name", $name)';
		throw 'Security Error: Access to field "$field" is not allowed on non-whitelisted class "$name".\nHint: To allow field access to this class in your host application, add:\n  $hint';
	}

	inline function isInternalHaxiomClass(name:String):Bool {
		return (StringTools.startsWith(name, "haxiom.Haxiom") && name != "haxiom.Haxiom") ||
			name == "haxiom.DynamicMap" ||
			name == "haxiom.Scope" ||
			name == "haxiom.VMFiber";
	}

	function isImportWhitelisted(fqName:String):Bool {
		var auto = isAutoWhitelisted(fqName);
		if (auto)
			return true;

		if (fqName == "String" || fqName == "Array" || fqName == "Xml" || fqName == "Math" || fqName == "Std" || fqName == "EReg") {
			return true;
		}

		var isNative = (Type.resolveClass(fqName) != null) || (Type.resolveEnum(fqName) != null);
		// haxe.Log.trace("isImportWhitelisted check for " + fqName + ": isNative=" + isNative, null);
		if (isNative) {
			// haxe.Log.trace("isImportWhitelisted check for " + fqName + ": importWhitelist=" + importWhitelist, null);
			if (importWhitelist == null)
				return true;
			for (pattern in importWhitelist) {
				if (pattern == fqName)
					return true;
				if (StringTools.endsWith(pattern, "*")) {
					var prefix = pattern.substring(0, pattern.length - 1);
					if (StringTools.startsWith(fqName, prefix))
						return true;
				}
			}
			return false;
		}

		return true;
	}

	function getClassNameOf(o:Dynamic):String {
		if (o == null)
			return null;
		if (Std.isOfType(o, String))
			return o;
		if (Reflect.isObject(o)) {
			var cl = Type.getClass(o);
			if (cl != null) {
				return Type.getClassName(cl);
			}
			try {
				var name = Type.getClassName(cast o);
				if (name != null)
					return name;
			} catch (e:Dynamic) {}
		}
		return null;
	}

	public function checkSafeToSerialize(v:Dynamic) {
		var visited = new haxe.ds.ObjectMap<Dynamic, Bool>();
		_checkSafeToSerialize(v, visited);
	}

	function _checkSafeToSerialize(v:Dynamic, visited:haxe.ds.ObjectMap<Dynamic, Bool>) {
		if (v == null) return;
		switch (Type.typeof(v)) {
			case TObject | TClass(_):
				if (visited.exists(v)) return;
				visited.set(v, true);
			default:
		}

		switch (Type.typeof(v)) {
			case TObject:
				for (field in Reflect.fields(v)) {
					_checkSafeToSerialize(Reflect.field(v, field), visited);
				}
			case TClass(c):
				if (c == Array) {
					var arr:Array<Dynamic> = cast v;
					for (item in arr) {
						_checkSafeToSerialize(item, visited);
					}
				} else {
					var className = Type.getClassName(c);
					if (importWhitelist != null && className != null && !isInternalHaxiomClass(className) && !isImportWhitelisted(className)) {
						throw "Security Error: Cannot serialize non-whitelisted class instance of " + className;
					}
					if (Std.isOfType(v, haxe.Constraints.IMap)) {
						var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast v;
						for (key in map.keys()) {
							_checkSafeToSerialize(map.get(key), visited);
						}
					} else {
						for (field in Reflect.fields(v)) {
							_checkSafeToSerialize(Reflect.field(v, field), visited);
						}
					}
				}
			default:
		}
	}

	function getSafeTypeProxy():Dynamic {
		return {
			resolveClass: function(name:String) {
				if (importWhitelist != null && !isImportWhitelisted(name))
					return null;
				return resolveNativeClass(name);
			},
			resolveEnum: function(name:String) {
				if (importWhitelist != null && !isImportWhitelisted(name))
					return null;
				return Type.resolveEnum(name);
			},
			createInstance: function(cl:Dynamic, args:Array<Dynamic>) {
				if (cl != null && importWhitelist != null) {
					var className = getClassNameOf(cl);
					if (className != null && !isInternalHaxiomClass(className) && !isImportWhitelisted(className)) {
						throw "Security Error: Type.createInstance is not allowed for class " + className;
					}
				}
				return Type.createInstance(cl, args);
			},
			createEmptyInstance: function(cl:Dynamic) {
				if (cl != null && importWhitelist != null) {
					var className = getClassNameOf(cl);
					if (className != null && !isInternalHaxiomClass(className) && !isImportWhitelisted(className)) {
						throw "Security Error: Type.createEmptyInstance is not allowed for class " + className;
					}
				}
				return Type.createEmptyInstance(cl);
			},
			getClass: Type.getClass,
			getSuperClass: Type.getSuperClass,
			getClassName: Type.getClassName,
			getClassFields: function(c:Dynamic) {
				if (c != null && importWhitelist != null) {
					var name = getClassNameOf(c);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Type.getClassFields is not allowed for class " + name;
					}
				}
				return Type.getClassFields(c);
			},
			getInstanceFields: function(c:Dynamic) {
				if (c != null && importWhitelist != null) {
					var name = getClassNameOf(c);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Type.getInstanceFields is not allowed for class " + name;
					}
				}
				return Type.getInstanceFields(c);
			},
			typeof: Type.typeof,
			enumEq: Type.enumEq,
			getEnumName: Type.getEnumName,
			getEnumConstructs: Type.getEnumConstructs,
			allEnums: Type.allEnums
		};
	}

	function getSafeReflectProxy():Dynamic {
		return {
			field: function(o:Dynamic, field:String) {
				if (o != null && importWhitelist != null) {
					var name = getClassNameOf(o);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Reflect.field is not allowed for class " + name;
					}
				}
				if (o == haxe.Json && field == "stringify") {
					return (cast function(value:Dynamic, ?replacer:Dynamic, ?space:String):String {
						checkSafeToSerialize(value);
						return haxe.Json.stringify(value, replacer, space);
					} : Dynamic);
				}
				if (o == haxe.Serializer && field == "run") {
					return (cast function(v:Dynamic) {
						checkSafeToSerialize(v);
						return haxe.Serializer.run(v);
					} : Dynamic);
				}
				return Reflect.field(o, field);
			},
			setField: function(o:Dynamic, field:String, value:Dynamic) {
				if (o != null && importWhitelist != null) {
					var name = getClassNameOf(o);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Reflect.setField is not allowed for class " + name;
					}
				}
				if (o != null) {
					if (Std.isOfType(o, HaxiomInstance)) {
						var inst:HaxiomInstance = cast o;
						if (!inst.fields.exists(field)) {
							trackMemory(1);
						}
					} else if (Type.typeof(o) == TObject) {
						if (!Reflect.hasField(o, field)) {
							trackMemory(1);
						}
					}
				}
				Reflect.setField(o, field, value);
			},
			getProperty: function(o:Dynamic, field:String) {
				if (o != null && importWhitelist != null) {
					var name = getClassNameOf(o);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Reflect.getProperty is not allowed for class " + name;
					}
				}
				if (o == haxe.Json && field == "stringify") {
					return (cast function(value:Dynamic, ?replacer:Dynamic, ?space:String):String {
						checkSafeToSerialize(value);
						return haxe.Json.stringify(value, replacer, space);
					} : Dynamic);
				}
				if (o == haxe.Serializer && field == "run") {
					return (cast function(v:Dynamic) {
						checkSafeToSerialize(v);
						return haxe.Serializer.run(v);
					} : Dynamic);
				}
				return Reflect.getProperty(o, field);
			},
			setProperty: function(o:Dynamic, field:String, value:Dynamic) {
				if (o != null && importWhitelist != null) {
					var name = getClassNameOf(o);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Reflect.setProperty is not allowed for class " + name;
					}
				}
				if (o != null) {
					if (Std.isOfType(o, HaxiomInstance)) {
						var inst:HaxiomInstance = cast o;
						if (!inst.fields.exists(field)) {
							trackMemory(1);
						}
					} else if (Type.typeof(o) == TObject) {
						if (!Reflect.hasField(o, field)) {
							trackMemory(1);
						}
					}
				}
				Reflect.setProperty(o, field, value);
			},
			callMethod: function(o:Dynamic, func:Dynamic, args:Array<Dynamic>) {
				if (o != null && importWhitelist != null) {
					var name = getClassNameOf(o);
					if (name != null && !isInternalHaxiomClass(name) && !isImportWhitelisted(name)) {
						throw "Security Error: Reflect.callMethod is not allowed for class " + name;
					}
				}
				return Reflect.callMethod(o, func, args);
			},
			hasField: Reflect.hasField,
			fields: Reflect.fields,
			isFunction: Reflect.isFunction,
			compare: Reflect.compare,
			compareMethods: Reflect.compareMethods,
			isObject: Reflect.isObject,
			isEnumValue: Reflect.isEnumValue,
			deleteField: Reflect.deleteField,
			copy: Reflect.copy,
			makeVarArgs: Reflect.makeVarArgs
		};
	}

	function findAbstractOpMethod(abs:HaxiomAbstract, op:String, isBinop:Bool):Null<Dynamic> {
		for (mName in abs.methods.keys()) {
			var m = abs.methods.get(mName);
			if (m.meta != null) {
				for (meta in m.meta) {
					if (meta.name == ":op" || meta.name == "op") {
						if (meta.params != null && meta.params.length > 0) {
							var paramExpr:Expr = cast meta.params[0];
							if (paramExpr != null) {
								switch (paramExpr.def) {
									case EBinop(o, _, _) if (isBinop && o == op):
										return m;
									case EUnop(o, _) if (!isBinop && o == op):
										return m;
									default:
								}
							}
						}
					}
				}
			}
		}
		return null;
	}

	function findAbstractBinopOverload(op:String, v1:Dynamic, v2:Dynamic):{success:Bool, value:Dynamic} {
		if (Std.isOfType(v1, HaxiomAbstractInstance)) {
			var inst:HaxiomAbstractInstance = cast v1;
			var method = findAbstractOpMethod(inst.abstractType, op, true);
			if (method != null) {
				return {success: true, value: callAbstractOp(inst.abstractType, method, [v1, v2])};
			}
		}
		if (Std.isOfType(v2, HaxiomAbstractInstance)) {
			var inst:HaxiomAbstractInstance = cast v2;
			var method = findAbstractOpMethod(inst.abstractType, op, true);
			if (method != null) {
				return {success: true, value: callAbstractOp(inst.abstractType, method, [v1, v2])};
			}
		}
		return {success: false, value: null};
	}

	function findAbstractUnopOverload(op:String, val:Dynamic):{success:Bool, value:Dynamic} {
		if (Std.isOfType(val, HaxiomAbstractInstance)) {
			var inst:HaxiomAbstractInstance = cast val;
			var method = findAbstractOpMethod(inst.abstractType, op, false);
			if (method != null) {
				return {success: true, value: callAbstractOp(inst.abstractType, method, [val])};
			}
		}
		return {success: false, value: null};
	}

	function callAbstractOp(abs:HaxiomAbstract, method:Dynamic, args:Array<Dynamic>):Dynamic {
		var func = bindMethod(null, method);
		return Reflect.callMethod(null, func, args);
	}

	function resolveNativeClass(fqName:String):Dynamic {
		if (fqName == "haxiom.Haxiom" || fqName == "haxiom.Interp" || fqName == "haxiom.VM" || fqName == "haxiom.FFI") {
			return null;
		}
		if (!isImportWhitelisted(fqName)) {
			return null;
		}
		if (fqName == "Type") {
			return getSafeTypeProxy();
		}
		if (fqName == "Reflect") {
			return getSafeReflectProxy();
		}
		if (fqName == "haxe.rtti.Meta") {
			return HaxiomMeta;
		}
		if (fqName == "haxe.ds.Vector") {
			var c = Type.resolveClass("haxe.ds.Vector");
			if (c != null)
				return c;
			return {__isHaxiomVectorClass: true};
		}
		var registryCls = Type.resolveClass("haxiom.macro.StdlibRegistry");
		if (registryCls != null) {
			var classes:Map<String, Dynamic> = Reflect.field(registryCls, "classes");
			if (classes != null && classes.exists(fqName)) {
				return classes.get(fqName);
			}
		}
		return Type.resolveClass(fqName);
	}

	function resolveAbstractImpl(absName:String, implClassName:String):Dynamic {
		var implCls = this.ffi.abstractImpls.get(absName);
		if (implCls == null) {
			implCls = resolveNativeClass(implClassName);
		}
		return implCls;
	}

	function getOrLoadModule(fqName:String):Scope {
		if (importedModules.exists(fqName)) {
			return importedModules.get(fqName);
		}
		if (moduleResolver != null) {
			var src = moduleResolver(fqName);
			if (src != null) {
				var moduleScope = new Scope(globals);
				var lexer = new Lexer(src, fqName, preprocessorFlags);
				var tokens = lexer.tokenize();
				var parser = new Parser(tokens);
				var ast = parser.parse();

				var oldPkg = currentPackage;
				currentPackage = [];

				switch (ast.def) {
					case EBlock(exprs):
						for (expr in exprs) {
							eval(expr, moduleScope);
						}
					default:
						eval(ast, moduleScope);
				}

				currentPackage = oldPkg;

				importedModules.set(fqName, moduleScope);
				return moduleScope;
			}
		}
		return null;
	}

	inline function isTruthy(v:Dynamic):Bool {
		return v != null && v != false;
	}

	function safeHasField(obj:Dynamic, field:String):Bool {
		if (obj == null)
			return false;
		if (!Reflect.isObject(obj))
			return false;
		try {
			return Reflect.hasField(obj, field);
		} catch (e:Dynamic) {
			return false;
		}
	}

	function safeField(obj:Dynamic, field:String):Dynamic {
		if (obj == null)
			return null;
		try {
			var res = Reflect.getProperty(obj, field);
			if (res == null) {
				res = Reflect.field(obj, field);
			}
			return res;
		} catch (e:Dynamic) {
			return null;
		}
	}

	function safeFields(obj:Dynamic):Array<String> {
		if (obj == null)
			return [];
		try {
			return Reflect.fields(obj);
		} catch (e:Dynamic) {
			return [];
		}
	}

	function safeGetClassName(cl:Dynamic):String {
		if (cl == null)
			return null;
		try {
			return Type.getClassName(cast cl);
		} catch (e:Dynamic) {
			return null;
		}
	}
}

class FunctionSignatures {
	#if neko
	var pairs:Array<{k:Dynamic, v:haxiom.TypeDecl}> = [];
	#else
	var map:haxe.ds.ObjectMap<Dynamic, haxiom.TypeDecl> = new haxe.ds.ObjectMap();
	#end

	public function new() {}

	public function set(k:Dynamic, v:haxiom.TypeDecl) {
		#if neko
		for (p in pairs) {
			if (p.k == k) {
				p.v = v;
				return;
			}
		}
		pairs.push({k: k, v: v});
		#else
		map.set(k, v);
		#end
	}

	public function exists(k:Dynamic):Bool {
		#if neko
		for (p in pairs) {
			if (p.k == k)
				return true;
		}
		return false;
		#else
		return map.exists(k);
		#end
	}

	public function get(k:Dynamic):haxiom.TypeDecl {
		#if neko
		for (p in pairs) {
			if (p.k == k)
				return p.v;
		}
		return null;
		#else
		return map.get(k);
		#end
	}
}
