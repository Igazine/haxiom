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
@:allow(haxiom)
class HaxiomClass {
	private var name:String;
	private var params:Array<TypeParamDef> = [];
	private var parentType:TypeDecl;
	private var parent:HaxiomClass;
	private var isAbstract:Bool = false;
	private var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?bytecodeChunk:haxiom.VM.BytecodeChunk,
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	private var methods:Map<String, ClassMethodInfo> = new Map();
	private var staticFields:Map<String, Dynamic> = new Map();
	private var interfaces:Array<TypeDecl> = [];
	private var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	private function new(name:String, ?parent:HaxiomClass) {
		this.name = name;
		this.parent = parent;
	}
}

@:keep
@:allow(haxiom)
class HaxiomInterface {
	private var name:String;
	private var params:Array<TypeParamDef> = [];
	private var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		?property:{get:String, set:String},
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	private var methods:Map<String, {
		name:String,
		args:Array<FunctionArg>,
		retType:Null<TypeDecl>,
		?body:Null<Expr>,
		?params:Array<TypeParamDef>,
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	private var parents:Array<TypeDecl> = [];
	private var meta:Array<{name:String, params:Array<Dynamic>}> = [];

	private function new(name:String, ?parents:Array<TypeDecl>) {
		this.name = name;
		this.parents = parents != null ? parents : [];
	}
}

@:keep
@:allow(haxiom)
class HaxiomInstance {
	private var cls:HaxiomClass;
	private var fields:Map<String, Dynamic> = new Map();
	private var genericBindings:Map<String, TypeDecl> = new Map();

	private function new(cls:HaxiomClass) {
		this.cls = cls;
	}
}

@:keep
@:allow(haxiom)
class HaxiomEnum {
	private var name:String;
	private var constructors:Map<String, Array<{name:String, type:Null<TypeDecl>}>> = new Map();
	private var params:Array<TypeParamDef> = [];

	private function new(name:String) {
		this.name = name;
	}
}

@:keep
@:allow(haxiom)
class HaxiomEnumInstance {
	private var enumType:HaxiomEnum;
	private var constructorName:String;
	private var args:Array<Dynamic>;

	private function new(enumType:HaxiomEnum, constructorName:String, args:Array<Dynamic>) {
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
@:allow(haxiom)
class HaxiomAbstract {
	private var name:String;
	private var params:Array<TypeParamDef> = [];
	private var underlyingType:TypeDecl;
	private var fields:Map<String, {
		name:String,
		type:Null<TypeDecl>,
		expr:Expr,
		isStatic:Bool,
		isPublic:Bool,
		isFinal:Bool,
		?property:{get:String, set:String},
		?bytecodeChunk:haxiom.VM.BytecodeChunk,
		?meta:Array<{name:String, params:Array<Dynamic>}>
	}> = new Map();
	private var methods:Map<String, ClassMethodInfo> = new Map();
	private var staticFields:Map<String, Dynamic> = new Map();
	private var meta:Array<{name:String, params:Array<Dynamic>}> = [];
	private var fromTypes:Array<String> = [];
	private var toTypes:Array<String> = [];

	private function new(name:String, underlyingType:TypeDecl) {
		this.name = name;
		this.underlyingType = underlyingType;
	}
}

@:keep
@:allow(haxiom)
class HaxiomAbstractInstance {
	private var abstractType:HaxiomAbstract;
	private var underlyingValue:Dynamic;

	private function new(abstractType:HaxiomAbstract, underlyingValue:Dynamic) {
		this.abstractType = abstractType;
		this.underlyingValue = underlyingValue;
	}
}
