package haxiom;

import haxe.ds.ObjectMap;
import haxe.io.Bytes;
import haxiom.HaxiomTypes.HaxiomAbstract;
import haxiom.HaxiomTypes.HaxiomAbstractInstance;
import haxiom.HaxiomTypes.HaxiomClass;
import haxiom.HaxiomTypes.HaxiomEnum;
import haxiom.HaxiomTypes.HaxiomEnumInstance;
import haxiom.HaxiomTypes.HaxiomInstance;
import haxiom.HaxiomTypes.HaxiomInterface;
import haxiom.ProxyBoundaryType.ProxyBoundaryField;

@:allow(haxiom)
final class ProxyBoundary {
	private static function convert(value:Dynamic, type:ProxyBoundaryType, path:String):Dynamic {
		return convertValue(value, type, path, new ObjectMap<Dynamic, Dynamic>());
	}

	static function convertValue(value:Dynamic, type:ProxyBoundaryType, path:String, seen:ObjectMap<Dynamic, Dynamic>):Dynamic {
		if (value == null) {
			if (type.nullable || type.kind == "dynamic" || type.kind == "void")
				return null;
			fail(path, 'expected ${type.kind}, got null');
		}

		return switch (type.kind) {
			case "void": null;
			case "bool": require(value, Std.isOfType(value, Bool), path, "Bool");
			case "int": require(value, Std.isOfType(value, Int), path, "Int");
			case "float": require(value, Std.isOfType(value, Float) || Std.isOfType(value, Int), path, "Float");
			case "string": require(value, Std.isOfType(value, String), path, "String");
			case "bytes": copyBytes(value, path);
			case "array": copyArray(value, type.element, path, seen);
			case "anonymous": copyAnonymous(value, type.fields, path, seen);
			case "hostref":
				if (Type.getClass(value) != HostRef)
					fail(path, "expected an exact haxiom.HostRef handle");
				value;
			case "dynamic": copyDynamic(value, path, seen);
			default: fail(path, 'unsupported boundary contract ${type.kind}');
		}
	}

	static function require(value:Dynamic, valid:Bool, path:String, expected:String):Dynamic {
		if (!valid)
			fail(path, 'expected $expected, got ${runtimeType(value)}');
		return value;
	}

	static function copyBytes(value:Dynamic, path:String):Bytes {
		if (!Std.isOfType(value, Bytes))
			fail(path, 'expected haxe.io.Bytes, got ${runtimeType(value)}');
		var source:Bytes = cast value;
		var copy = Bytes.alloc(source.length);
		copy.blit(0, source, 0, source.length);
		return copy;
	}

	static function copyArray(value:Dynamic, element:ProxyBoundaryType, path:String, seen:ObjectMap<Dynamic, Dynamic>):Array<Dynamic> {
		if (!Std.isOfType(value, Array))
			fail(path, 'expected Array, got ${runtimeType(value)}');
		if (seen.exists(value))
			return cast seen.get(value);
		var source:Array<Dynamic> = cast value;
		var copy:Array<Dynamic> = [];
		seen.set(value, copy);
		for (index in 0...source.length)
			copy.push(convertValue(source[index], element, '$path[$index]', seen));
		return copy;
	}

	static function copyAnonymous(value:Dynamic, fields:Array<ProxyBoundaryField>, path:String, seen:ObjectMap<Dynamic, Dynamic>):Dynamic {
		if (!isPlainStructure(value))
			fail(path, 'expected an anonymous structure, got ${runtimeType(value)}');
		if (seen.exists(value))
			return seen.get(value);
		var copy:Dynamic = {};
		seen.set(value, copy);
		for (field in fields) {
			if (!Reflect.hasField(value, field.name)) {
				if (!field.optional)
					fail('$path.${field.name}', "required field is missing");
				continue;
			}
			Reflect.setField(copy, field.name, convertValue(Reflect.field(value, field.name), field.type, '$path.${field.name}', seen));
		}
		return copy;
	}

	static function copyDynamic(value:Dynamic, path:String, seen:ObjectMap<Dynamic, Dynamic>):Dynamic {
		if (value == null || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float) || Std.isOfType(value, String))
			return value;
		if (Std.isOfType(value, Bytes))
			return copyBytes(value, path);
		if (Type.getClass(value) == HostRef)
			return value;
		if (Std.isOfType(value, Array))
			return copyArray(value, new ProxyBoundaryType("dynamic", true), path, seen);
		if (isGuestRuntimeValue(value))
			fail(path, "raw guest runtime values cannot cross a typed interface boundary");
		if (Reflect.isFunction(value))
			fail(path, "functions cannot cross a typed interface boundary");
		if (isPlainStructure(value)) {
			if (seen.exists(value))
				return seen.get(value);
			var copy:Dynamic = {};
			seen.set(value, copy);
			for (field in Reflect.fields(value))
				Reflect.setField(copy, field, copyDynamic(Reflect.field(value, field), '$path.$field', seen));
			return copy;
		}
		return fail(path, 'native object ${runtimeType(value)} requires an explicit supported type or HostRef');
	}

	static function isPlainStructure(value:Dynamic):Bool {
		if (value == null || Reflect.isFunction(value) || isGuestRuntimeValue(value))
			return false;
		return switch (Type.typeof(value)) {
			case TObject: true;
			default: false;
		}
	}

	static function isGuestRuntimeValue(value:Dynamic):Bool {
		return Std.isOfType(value, HaxiomInstance) || Std.isOfType(value, HaxiomClass) || Std.isOfType(value, HaxiomInterface)
			|| Std.isOfType(value, HaxiomEnum) || Std.isOfType(value, HaxiomEnumInstance) || Std.isOfType(value, HaxiomAbstract)
			|| Std.isOfType(value, HaxiomAbstractInstance);
	}

	static function runtimeType(value:Dynamic):String {
		if (value == null)
			return "null";
		var cls = Type.getClass(value);
		if (cls != null)
			return Type.getClassName(cls);
		var enm = Type.getEnum(value);
		if (enm != null)
			return Type.getEnumName(enm);
		return Std.string(Type.typeof(value));
	}

	static function fail(path:String, reason:String):Dynamic {
		throw 'Typed interface boundary violation at $path: $reason';
	}
}
