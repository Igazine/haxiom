package haxiom;

import haxiom.VM.BytecodeChunk;

/** Restricts HXBC constant deserialization to Haxiom's persisted data types. */
@:allow(haxiom)
class HXBCTypeResolver {
	public function new() {}

	public function resolveClass(name:String):Class<Dynamic> {
		return switch (name) {
			case "haxiom.BinaryBytesHolder": cast BinaryBytesHolder;
			case "haxiom.BinaryExprHolder": cast BinaryExprHolder;
			case "haxiom.BinaryResourceRefHolder": cast BinaryResourceRefHolder;
			case "haxiom.BytecodeChunk" | "haxiom.VM.BytecodeChunk": cast BytecodeChunk;
			default: null;
		};
	}

	public function resolveEnum(name:String):Enum<Dynamic> {
		if (name == null || !StringTools.startsWith(name, "haxiom."))
			return null;
		return Type.resolveEnum(name);
	}
}
