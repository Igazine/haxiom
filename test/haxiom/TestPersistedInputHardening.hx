package haxiom;

import haxe.crypto.Adler32;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

class TestPersistedInputHardening {
	public static function runTests():Void {
		testPortableASTRejection();
		testHXBCHeaderRejection();
		testCompressedPayloadRejection();
		testVerifiedPayloadRejection();
		testConfiguredSizeLimit();
		trace("SUCCESS: Persisted input hardening verified.");
	}

	static function testPortableASTRejection():Void {
		assertRejected("null AST", () -> new Haxiom().executeASTBytes(null), "data is null");
		assertRejected("invalid AST JSON", () -> new Haxiom().executeASTBytes(Bytes.ofString("not-json")), null);
		assertRejected("missing AST root tag", () -> new Haxiom().executeASTBytes(Bytes.ofString("{}")), "root expression");
		assertRejected("scalar AST root", () -> new Haxiom().executeASTBytes(Bytes.ofString("0")), "root expression");

		var depthEngine = new Haxiom();
		depthEngine.maxPersistedDepth = 4;
		assertRejected("deep AST JSON", () -> depthEngine.executeASTBytes(Bytes.ofString("[[[[[0]]]]]")), "nesting exceeds limit");
	}

	static function testHXBCHeaderRejection():Void {
		assertRejected("null HXBC", () -> new Haxiom().executeBytecodeBytes(null), "data is null");
		assertRejected("short HXBC", () -> new Haxiom().executeBytecodeBytes(Bytes.ofString("HXBC")), "too short");
		assertRejected("invalid HXBC magic", () -> new Haxiom().executeBytecodeBytes(header(emptyPayload(), 0, 0, null, "NOPE")), "magic");
		assertRejected("unsupported HXBC version", () -> new Haxiom().executeBytecodeBytes(header(emptyPayload(), 0, 0, null, null, 2)),
			"Unsupported bytecode version");
		assertRejected("unknown HXBC flags", () -> new Haxiom().executeBytecodeBytes(header(emptyPayload(), 0x80)), "flags");
		assertRejected("negative HXBC slots", () -> new Haxiom().executeBytecodeBytes(header(emptyPayload(), 0, -1)), "negative maxSlots");
		assertRejected("raw HXBC size mismatch", () -> new Haxiom().executeBytecodeBytes(header(emptyPayload(), 0, 0, 999)),
			"payload length mismatch");
	}

	static function testCompressedPayloadRejection():Void {
		var mismatchedBlock = Bytes.alloc(5);
		writeInt32LE(mismatchedBlock, 0, 2);
		mismatchedBlock.set(4, 0);
		assertRejected("LZ4 length mismatch", () -> new Haxiom().executeBytecodeBytes(header(mismatchedBlock, 4, 0, 1)),
			"Uncompressed length mismatch");

		var incompleteBlock = Bytes.alloc(5);
		writeInt32LE(incompleteBlock, 0, 1);
		incompleteBlock.set(4, 0);
		assertRejected("truncated LZ4 output", () -> new Haxiom().executeBytecodeBytes(header(incompleteBlock, 4, 0, 1)),
			"Output length mismatch");

		var oversizedBlock = Bytes.alloc(4);
		writeInt32LE(oversizedBlock, 0, 65 * 1024 * 1024);
		assertRejected("oversized compressed HXBC", () -> new Haxiom().executeBytecodeBytes(header(oversizedBlock, 4, 0, 65 * 1024 * 1024)),
			"decoded payload exceeds limit");
	}

	static function testVerifiedPayloadRejection():Void {
		assertRejected("invalid serialized opcode", () -> new Haxiom().executeBytecodeBytes(header(bytecodePayload([99]))), "Invalid opcode");
		assertRejected("missing serialized operand", () -> new Haxiom().executeBytecodeBytes(header(bytecodePayload([1]))), "missing 1 operand");
		assertRejected("negative serialized element count", () -> new Haxiom().executeBytecodeBytes(header(bytecodePayload([37, -1]))),
			"negative element count");

		var hugeCount = new BytesOutput();
		hugeCount.bigEndian = false;
		writeVarInt(hugeCount, 0x7FFFFFFF);
		assertRejected("oversized serialized table", () -> new Haxiom().executeBytecodeBytes(header(hugeCount.getBytes())),
			"string pool count exceeds limit");
		assertRejected("invalid serialized varint marker", () -> new Haxiom().executeBytecodeBytes(header(Bytes.ofHex("FF"))),
			"variable integer marker");

		var info = Haxiom.inspectBytecode(header(emptyPayload(), 0x80));
		if (info.status != "CORRUPTED")
			throw 'Malformed HXBC inspection must report CORRUPTED, got ${info.status}';
	}

	static function testConfiguredSizeLimit():Void {
		var source = "class PersistedLimitMain { static public function main() return 42; }";
		var bytes = new Haxiom().compileToBytecodeBytes(source, new ScriptContext("PersistedLimitMain"));
		var engine = new Haxiom();
		engine.maxPersistedBytes = bytes.length - 1;
		assertRejected("configured HXBC size limit", () -> engine.executeBytecodeBytes(bytes), "encoded payload exceeds limit");

		var astBytes = new Haxiom().compileToASTBytes(source, new ScriptContext("PersistedLimitMain"));
		var astEngine = new Haxiom();
		astEngine.maxPersistedBytes = astBytes.length - 1;
		assertRejected("configured AST size limit", () -> astEngine.executeASTBytes(astBytes), "payload exceeds limit");
		assertRejected("negative persisted size limit", () -> engine.maxPersistedBytes = -1, "cannot be negative");
		assertRejected("negative persisted depth limit", () -> engine.maxPersistedDepth = -1, "cannot be negative");
	}

	static function bytecodePayload(instructions:Array<Int>):Bytes {
		var out = new BytesOutput();
		out.bigEndian = false;
		writeVarInt(out, 0); // string pool
		writeVarInt(out, instructions.length);
		for (instruction in instructions)
			writeVarInt(out, instruction);
		writeVarInt(out, 0); // positions
		var constants = Bytes.ofString(haxe.Serializer.run([]));
		writeVarInt(out, constants.length);
		out.write(constants);
		writeVarInt(out, 0); // debug symbols
		writeVarInt(out, 0); // resources
		writeVarInt(out, 0); // script name
		return out.getBytes();
	}

	static function emptyPayload():Bytes {
		return bytecodePayload([]);
	}

	static function header(payload:Bytes, ?flags:Int = 0, ?maxSlots:Int = 0, ?uncompressedSize:Int, ?magic:String = "HXBC", ?version:Int = 1):Bytes {
		var out = new BytesOutput();
		out.bigEndian = false;
		out.writeString(magic);
		out.writeByte(version);
		out.writeByte(flags);
		out.writeInt32(maxSlots);
		out.writeInt32(uncompressedSize == null ? payload.length : uncompressedSize);
		out.writeInt32(Adler32.make(payload));
		out.write(payload);
		return out.getBytes();
	}

	static function writeVarInt(out:BytesOutput, value:Int):Void {
		if (value >= 0 && value < 240) {
			out.writeByte(value);
		} else if (value >= 0 && value < 65536) {
			out.writeByte(240);
			out.writeUInt16(value);
		} else {
			out.writeByte(241);
			out.writeInt32(value);
		}
	}

	static function writeInt32LE(bytes:Bytes, offset:Int, value:Int):Void {
		bytes.set(offset, value & 0xFF);
		bytes.set(offset + 1, (value >> 8) & 0xFF);
		bytes.set(offset + 2, (value >> 16) & 0xFF);
		bytes.set(offset + 3, (value >> 24) & 0xFF);
	}

	static function assertRejected(label:String, fn:Void->Void, expected:String):Void {
		try {
			fn();
		} catch (e:Dynamic) {
			var message = Std.string(e);
			if (expected == null || message.indexOf(expected) != -1)
				return;
			throw '$label produced unexpected error: $message';
		}
		throw '$label was accepted';
	}
}
