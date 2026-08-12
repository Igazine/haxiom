package haxiom;

import haxe.crypto.Adler32;
import haxe.crypto.Sha1;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxiom.VM.BytecodeChunk;

class TestPersistedInputHardening {
	public static function runTests():Void {
		testPortableASTRejection();
		testHXBCHeaderRejection();
		testCompressedPayloadRejection();
		testVerifiedPayloadRejection();
		testAdversarialBytecodeMutations();
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

	static function testAdversarialBytecodeMutations():Void {
		var cases = [
			{
				name: "jump into operand",
				payload: bytecodePayload([28, 1]),
				maxSlots: 0,
				expected: "not an instruction boundary"
			},
			{
				name: "exception handler into operand",
				payload: bytecodePayload([48, 1]),
				maxSlots: 0,
				expected: "not an instruction boundary"
			},
			{
				name: "constant index overflow",
				payload: bytecodePayload([1, 0]),
				maxSlots: 0,
				expected: "Constant index 0 out of bounds"
			},
			{
				name: "wrong constant shape",
				payload: bytecodePayload([4, 0], [42]),
				maxSlots: 0,
				expected: "variable name string"
			},
			{
				name: "local slot overflow",
				payload: bytecodePayload([2, 0]),
				maxSlots: 0,
				expected: "Local slot index"
			},
			{
				name: "oversized frame",
				payload: bytecodePayload([]),
				maxSlots: 1048577,
				expected: "exceeds VM safety limit"
			},
			{
				name: "map count overflow",
				payload: bytecodePayload([70, 0x7FFFFFFF]),
				maxSlots: 0,
				expected: "Map element count"
			},
			{
				name: "data stack underflow",
				payload: bytecodePayload([7]),
				maxSlots: 0,
				expected: "Stack underflow"
			},
			{
				name: "non-async await",
				payload: bytecodePayload([74]),
				maxSlots: 0,
				expected: "Await opcode in non-async"
			},
			{
				name: "position table mismatch",
				payload: bytecodePayload([0], [], [{count: 2, line: 1, col: 1, fileIdx: -1}]),
				maxSlots: 0,
				expected: "Position table length"
			},
			{
				name: "invalid debug symbol slot",
				payload: bytecodePayload([], [], [], [{nameIdx: 0, slot: 0, startIp: 0, endIp: 0}], ["local"]),
				maxSlots: 0,
				expected: "Debug symbol slot"
			},
			{
				name: "invalid script name index",
				payload: bytecodePayload([], [], [], [], [], 1),
				maxSlots: 0,
				expected: "script name index"
			},
			{
				name: "trailing payload data",
				payload: bytecodePayload([], [], [], [], [], -1, Bytes.ofHex("00")),
				maxSlots: 0,
				expected: "trailing payload data"
			},
			{
				name: "host class in constants",
				payload: bytecodePayload([], [new PersistedHostObject()]),
				maxSlots: 0,
				expected: "is not allowed"
			}
		];
		cases.push({
			name: "constant allocation bomb",
			payload: bytecodePayload([], null, null, null, null, -1, null, "au1000000h"),
			maxSlots: 0,
			expected: "null run exceeds limit"
		});
		var deeplyNested = "";
		for (_ in 0...300)
			deeplyNested += "a";
		deeplyNested += "n";
		for (_ in 0...300)
			deeplyNested += "h";
		cases.push({
			name: "deep constant graph",
			payload: bytecodePayload([], null, null, null, null, -1, null, deeplyNested),
			maxSlots: 0,
			expected: "nesting exceeds limit"
		});
		cases.push({
			name: "trailing constant value",
			payload: bytecodePayload([], null, null, null, null, -1, null, "ahz"),
			maxSlots: 0,
			expected: "trailing constant payload"
		});

		var nested = new BytecodeChunk([99], [], [], 0);
		cases.push({
			name: "invalid nested chunk",
			payload: bytecodePayload([41, 0], [{args: [], bodyChunk: nested}]),
			maxSlots: 0,
			expected: "Invalid opcode"
		});

		for (testCase in cases)
			assertPayloadRejectedEveryEncoding(testCase.name, testCase.payload, testCase.maxSlots, testCase.expected);
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

	static function bytecodePayload(instructions:Array<Int>, ?constants:Array<Dynamic>,
			?positionRuns:Array<{count:Int, line:Int, col:Int, fileIdx:Int}>,
			?debugSymbols:Array<{nameIdx:Int, slot:Int, startIp:Int, endIp:Int}>, ?stringPool:Array<String>, ?scriptNameIdx:Int = -1,
			?trailing:Bytes, ?serializedConstantData:String):Bytes {
		var out = new BytesOutput();
		out.bigEndian = false;
		if (constants == null)
			constants = [];
		if (positionRuns == null)
			positionRuns = [];
		if (debugSymbols == null)
			debugSymbols = [];
		if (stringPool == null)
			stringPool = [];

		writeVarInt(out, stringPool.length);
		for (value in stringPool) {
			var encoded = Bytes.ofString(value);
			writeVarInt(out, encoded.length);
			out.write(encoded);
		}
		writeVarInt(out, instructions.length);
		for (instruction in instructions)
			writeVarInt(out, instruction);
		writeVarInt(out, positionRuns.length);
		for (run in positionRuns) {
			writeVarInt(out, run.count);
			writeVarInt(out, run.line);
			writeVarInt(out, run.col);
			writeVarInt(out, run.fileIdx + 1);
		}
		var serializedConstants = Bytes.ofString(serializedConstantData != null ? serializedConstantData : haxe.Serializer.run(constants));
		writeVarInt(out, serializedConstants.length);
		out.write(serializedConstants);
		writeVarInt(out, debugSymbols.length);
		for (symbol in debugSymbols) {
			writeVarInt(out, symbol.nameIdx);
			writeVarInt(out, symbol.slot);
			writeVarInt(out, symbol.startIp);
			writeVarInt(out, symbol.endIp);
		}
		writeVarInt(out, 0); // resources
		writeVarInt(out, scriptNameIdx + 1);
		if (trailing != null)
			out.write(trailing);
		return out.getBytes();
	}

	static function assertPayloadRejectedEveryEncoding(label:String, payload:Bytes, maxSlots:Int, expected:String):Void {
		assertRejected(label + " (raw)", () -> new Haxiom().executeBytecodeBytes(encodedHeader(payload, payload, 0, maxSlots)), expected);

		var compressed = haxiom.LZ4.compress(payload);
		assertRejected(label + " (compressed)", () -> new Haxiom().executeBytecodeBytes(encodedHeader(compressed, payload, 4, maxSlots)), expected);

		var key:HXBCKey = "adversarial-bytecode-key";
		var encrypted = crypt(payload, key);
		var encryptedCompressed = haxiom.LZ4.compress(encrypted);
		assertRejected(label + " (keyed compressed)",
			() -> new Haxiom().executeBytecodeBytes(encodedHeader(encryptedCompressed, payload, 6, maxSlots), null, key), expected);
	}

	static function encodedHeader(encodedPayload:Bytes, decodedPayload:Bytes, flags:Int, maxSlots:Int):Bytes {
		var out = new BytesOutput();
		out.bigEndian = false;
		out.writeString("HXBC");
		out.writeByte(1);
		out.writeByte(flags);
		out.writeInt32(maxSlots);
		out.writeInt32(decodedPayload.length);
		out.writeInt32(Adler32.make(decodedPayload));
		out.write(encodedPayload);
		return out.getBytes();
	}

	static function crypt(data:Bytes, key:HXBCKey):Bytes {
		var keyHash = Sha1.make(Bytes.ofString(key.toString()));
		var result = Bytes.alloc(data.length);
		var state = 0;
		for (i in 0...data.length) {
			var k = keyHash.get(i % keyHash.length);
			state = (state + k + i) % 256;
			result.set(i, data.get(i) ^ state);
		}
		return result;
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

private class PersistedHostObject {
	public var value:Int = 1;

	public function new() {}
}
