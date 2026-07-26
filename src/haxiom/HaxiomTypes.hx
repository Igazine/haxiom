package haxiom;

import haxiom.AST;

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

@:keep
class HaxiomClass {
	public var name:String;
	public var params:Array<TypeParamDef> = [];
	public var parentType:TypeDecl;
	public var parent:HaxiomClass;
	public var isAbstract:Bool = false;
	public var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	public var methods:Map<String, ClassMethodInfo> = new Map();
	public var staticFields:Map<String, Dynamic> = new Map();
	public var interfaces:Array<TypeDecl> = [];
	public var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	public function new(name:String, ?parent:HaxiomClass) {
		this.name = name;
		this.parent = parent;
	}
}

@:keep
class HaxiomInterface {
	public var name:String;
	public var params:Array<TypeParamDef> = [];
	public var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	public var methods:Map<String, {
		name:String,
		args:Array<FunctionArg>,
		retType:Null<TypeDecl>,
		?body:Null<Expr>,
		?params:Array<TypeParamDef>,
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	public var parents:Array<TypeDecl> = [];
	public var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	public function new(name:String, ?parents:Array<TypeDecl>) {
		this.name = name;
		this.parents = parents != null ? parents : [];
	}
}

@:keep
class HaxiomInstance {
	public var cls:HaxiomClass;
	public var fields:Map<String, Dynamic> = new Map();
	public var genericBindings:Map<String, TypeDecl> = new Map();

	public function new(cls:HaxiomClass) {
		this.cls = cls;
	}
}

@:keep
class HaxiomEnum {
	public var name:String;
	public var constructors:Map<String, Array<{name:String, type:Null<TypeDecl>}>> = new Map();
	public var params:Array<TypeParamDef> = [];

	public function new(name:String) {
		this.name = name;
	}
}

@:keep
class HaxiomEnumInstance {
	public var enumType:HaxiomEnum;
	public var constructorName:String;
	public var args:Array<Dynamic>;

	public function new(enumType:HaxiomEnum, constructorName:String, args:Array<Dynamic>) {
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

@:keep
class HaxiomAbstract {
	public var name:String;
	public var params:Array<TypeParamDef> = [];
	public var underlyingType:TypeDecl;
	public var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	public var methods:Map<String, ClassMethodInfo> = new Map();
	public var staticFields:Map<String, Dynamic> = new Map();
	public var meta:Array<{name:String, params:Array<Dynamic>}> = [];
	public var fromTypes:Array<String> = [];
	public var toTypes:Array<String> = [];

	public function new(name:String, underlyingType:TypeDecl) {
		this.name = name;
		this.underlyingType = underlyingType;
	}
}

@:keep
class HaxiomAbstractInstance {
	public var abstractType:HaxiomAbstract;
	public var underlyingValue:Dynamic;

	public function new(abstractType:HaxiomAbstract, underlyingValue:Dynamic) {
		this.abstractType = abstractType;
		this.underlyingValue = underlyingValue;
	}
}
