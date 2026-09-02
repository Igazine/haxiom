package releaseconsumer;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
#end

class ApiBoundaryMacro {
	#if macro
	public static function verify():Void {
		assertPublic("haxiom.Haxiom", "interpret");
		assertPublic("haxiom.HostRef", "wrap", true);
		assertPublicConstructor("haxiom.ScriptContext");

		assertPrivate("haxiom.Interp", "state");
		assertPrivate("haxiom.MacroExpander", "expand", true);
		assertPrivate("haxiom.LZ4", "compress", true);
		assertPrivate("haxiom.ProxyBoundary", "convert", true);
		assertPrivate("haxiom.ProxyBoundaryType", "kind");
		assertPrivateConstructor("haxiom.ProxyBoundaryType");
		assertPrivate("haxiom.Haxiom", "invokeProxyMethod");
		assertPrivate("haxiom.Haxiom", "constructHelper", true);
		assertPrivate("haxiom.HaxiomTypes.HaxiomInstance", "fields");
		assertPrivateConstructor("haxiom.HaxiomTypes.HaxiomInstance");
		assertPrivate("haxiom.DynamicMap", "stringMap");
		assertPrivate("haxiom.ScriptException", "makeCodeFrame", true);
	}

	static function getClass(typeName:String):ClassType {
		return switch (Context.getType(typeName)) {
			case TInst(ref, _): ref.get();
			default: throw '$typeName is not a class';
		}
	}

	static function getField(typeName:String, fieldName:String, isStatic:Bool):ClassField {
		var cls = getClass(typeName);
		var fields = isStatic ? cls.statics.get() : cls.fields.get();
		for (field in fields) {
			if (field.name == fieldName)
				return field;
		}
		throw '$typeName.$fieldName was not found';
	}

	static function assertPublic(typeName:String, fieldName:String, ?isStatic:Bool = false):Void {
		if (!getField(typeName, fieldName, isStatic).isPublic)
			throw '$typeName.$fieldName must remain public';
	}

	static function assertPrivate(typeName:String, fieldName:String, ?isStatic:Bool = false):Void {
		if (getField(typeName, fieldName, isStatic).isPublic)
			throw '$typeName.$fieldName must remain private';
	}

	static function assertPublicConstructor(typeName:String):Void {
		var constructor = getClass(typeName).constructor;
		if (constructor == null || !constructor.get().isPublic)
			throw '$typeName constructor must remain public';
	}

	static function assertPrivateConstructor(typeName:String):Void {
		var constructor = getClass(typeName).constructor;
		if (constructor == null || constructor.get().isPublic)
			throw '$typeName constructor must remain private';
	}
	#end
}
