package haxiom;

import haxiom.AST.Expr;
import haxiom.VM.BytecodeChunk;
import haxiom.VM.DebugSymbol;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.crypto.Adler32;

class Serializer {
    public static function serialize(expr:Expr):String {
        var s = new haxe.Serializer();
        s.useCache = true;
        s.useEnumIndex = true;
        s.serialize(expr);
        return s.toString();
    }

    public static function deserialize(str:String):Expr {
        var u = new haxe.Unserializer(str);
        return u.unserialize();
    }

    public static function serializeToBytes(expr:Expr):Bytes {
        var str = serialize(expr);
        return Bytes.ofString(str);
    }

    public static function deserializeFromBytes(bytes:Bytes):Expr {
        return deserialize(bytes.toString());
    }

    static function crypt(data:Bytes, key:HXBCKey):Bytes {
        if (key == null || !key.isValid()) return data;
        var keyHash = haxe.crypto.Sha1.make(Bytes.ofString(key.toString()));
        var keyLen = keyHash.length;
        var result = Bytes.alloc(data.length);
        var state = 0;
        for (i in 0...data.length) {
            var k = keyHash.get(i % keyLen);
            state = (state + k + i) % 256;
            result.set(i, data.get(i) ^ state);
        }
        return result;
    }

    static function writeVarInt(out:BytesOutput, v:Int) {
        if (v >= 0 && v < 240) {
            out.writeByte(v);
        } else if (v >= 0 && v < 65536) {
            out.writeByte(240);
            out.writeUInt16(v);
        } else {
            out.writeByte(241);
            out.writeInt32(v);
        }
    }

    static function readVarInt(input:BytesInput):Int {
        var b = input.readByte();
        if (b < 240) {
            return b;
        } else if (b == 240) {
            return input.readUInt16();
        } else {
            return input.readInt32();
        }
    }

    static function shouldWrap(val:Dynamic):Bool {
        if (val == null) return false;
        if (Std.isOfType(val, BinaryExprHolder)) return false;
        return Reflect.hasField(val, "def") && Reflect.hasField(val, "pos");
    }

    public static function serializeBytecode(chunk:BytecodeChunk, ?key:HXBCKey):Bytes {
        var payloadOut = new BytesOutput();
        payloadOut.bigEndian = false;
        
        // 1. Build string pool for filenames and variable names
        var stringPool:Array<String> = [];
        var stringPoolMap = new Map<String, Int>();
        
        inline function addToStringPool(s:String):Int {
            if (s == null) return -1;
            if (stringPoolMap.exists(s)) return stringPoolMap.get(s);
            var idx = stringPool.length;
            stringPoolMap.set(s, idx);
            stringPool.push(s);
            return idx;
        }

        if (chunk.positions != null) {
            for (pos in chunk.positions) {
                if (pos != null && pos.file != null) {
                    addToStringPool(pos.file);
                }
            }
        }
        
        var debugSymbols = chunk.debugSymbols != null ? chunk.debugSymbols : [];
        for (sym in debugSymbols) {
            if (sym != null && sym.name != null) {
                addToStringPool(sym.name);
            }
        }
        
        // Write stringPool length and items
        writeVarInt(payloadOut, stringPool.length);
        for (s in stringPool) {
            var sBytes = Bytes.ofString(s);
            writeVarInt(payloadOut, sBytes.length);
            payloadOut.write(sBytes);
        }
        
        // 2. Write instructions
        var insts = chunk.instructions != null ? chunk.instructions : [];
        writeVarInt(payloadOut, insts.length);
        for (inst in insts) {
            writeVarInt(payloadOut, inst);
        }
        
        // 3. Write positions (RLE)
        var positions = chunk.positions != null ? chunk.positions : [];
        var rlePositions = [];
        if (positions.length > 0) {
            var currentPos = positions[0];
            var count = 1;
            for (i in 1...positions.length) {
                var p = positions[i];
                var identical = false;
                if (currentPos == null && p == null) {
                    identical = true;
                } else if (currentPos != null && p != null) {
                    identical = currentPos.line == p.line && currentPos.col == p.col && currentPos.file == p.file;
                }
                if (identical) {
                    count++;
                } else {
                    rlePositions.push({ pos: currentPos, count: count });
                    currentPos = p;
                    count = 1;
                }
            }
            rlePositions.push({ pos: currentPos, count: count });
        }
        
        writeVarInt(payloadOut, rlePositions.length);
        for (item in rlePositions) {
            writeVarInt(payloadOut, item.count);
            var pos = item.pos;
            if (pos == null) {
                writeVarInt(payloadOut, 0);
                writeVarInt(payloadOut, 0);
                writeVarInt(payloadOut, 0); // fileIdx + 1 = 0
            } else {
                writeVarInt(payloadOut, pos.line);
                writeVarInt(payloadOut, pos.col);
                var fileIdx = -1;
                if (pos.file != null) {
                    fileIdx = stringPoolMap.get(pos.file);
                }
                writeVarInt(payloadOut, fileIdx + 1);
            }
        }
        
        // 4. Write constants via Serializer
        var wrappedConstants = [];
        if (chunk.constants != null) {
            for (c in chunk.constants) {
                if (shouldWrap(c)) {
                    var serializedBytes = BinaryASTSerializer.serialize(c);
                    wrappedConstants.push(new BinaryExprHolder(serializedBytes));
                } else {
                    wrappedConstants.push(c);
                }
            }
        }
        var constsStr = haxe.Serializer.run(wrappedConstants);
        var constsBytes = Bytes.ofString(constsStr);
        writeVarInt(payloadOut, constsBytes.length);
        payloadOut.write(constsBytes);

        // 5. Write debug symbols
        writeVarInt(payloadOut, debugSymbols.length);
        for (sym in debugSymbols) {
            var nameIdx = stringPoolMap.get(sym.name);
            writeVarInt(payloadOut, nameIdx);
            writeVarInt(payloadOut, sym.slot);
            writeVarInt(payloadOut, sym.startIp);
            writeVarInt(payloadOut, sym.endIp);
        }
        
        // Compute Adler32 checksum of the unencrypted payload bytes
        var payloadBytes = payloadOut.getBytes();
        var checksum = Adler32.make(payloadBytes);
        
        // Encrypt if key is provided
        var encrypted = false;
        if (key != null && key.isValid()) {
            payloadBytes = crypt(payloadBytes, key);
            encrypted = true;
        }

        // Assemble final output
        var headerOut = new BytesOutput();
        headerOut.bigEndian = false;
        headerOut.writeString("HXBC");
        headerOut.writeByte(1); // Version 1
        
        // Flags byte: bit 0 = isAsync, bit 1 = isEncrypted
        var flags = (chunk.isAsync ? 1 : 0) | (encrypted ? 2 : 0);
        headerOut.writeByte(flags);
        
        headerOut.writeInt32(chunk.maxSlots);
        headerOut.writeInt32(checksum);
        headerOut.write(payloadBytes);
        
        return headerOut.getBytes();
    }

    public static function deserializeBytecode(bytes:Bytes, ?key:HXBCKey):BytecodeChunk {
        var input = new BytesInput(bytes);
        input.bigEndian = false;
        if (input.length < 14) {
            throw "Invalid bytecode: data too short";
        }
        
        var magic = input.readString(4);
        if (magic != "HXBC") {
            throw "Invalid bytecode magic header";
        }
        
        var version = input.readByte();
        if (version != 1) {
            throw 'Unsupported bytecode version $version';
        }
        
        var flags = input.readByte();
        var isAsync = (flags & 1) == 1;
        var isEncrypted = (flags & 2) == 2;
        var maxSlots = input.readInt32();
        var checksum = input.readInt32();
        
        if (isEncrypted && (key == null || !key.isValid())) {
            throw "Bytecode is encrypted and requires a key to load";
        }
        if (!isEncrypted && key != null && key.isValid()) {
            throw "Bytecode is not encrypted but a key was provided";
        }

        // Read payload
        var payloadBytes = input.read(input.length - 14);
        
        // Decrypt if encrypted
        if (isEncrypted) {
            payloadBytes = crypt(payloadBytes, key);
        }

        // Verify checksum of decrypted payload
        var computedChecksum = Adler32.make(payloadBytes);
        if (computedChecksum != checksum) {
            if (isEncrypted) {
                throw "Invalid encryption key or corrupted data";
            } else {
                throw "Bytecode checksum verification failed (data corrupted)";
            }
        }
        
        var payloadInput = new BytesInput(payloadBytes);
        payloadInput.bigEndian = false;
        
        // 1. Read string pool
        var stringPoolLength = readVarInt(payloadInput);
        var stringPool = [for (i in 0...stringPoolLength) {
            var len = readVarInt(payloadInput);
            payloadInput.readString(len);
        }];
        
        // 2. Read instructions
        var instsLength = readVarInt(payloadInput);
        var instructions = [for (i in 0...instsLength) readVarInt(payloadInput)];
        
        // 3. Read positions (RLE)
        var rleLength = readVarInt(payloadInput);
        var positions = [];
        for (i in 0...rleLength) {
            var count = readVarInt(payloadInput);
            var line = readVarInt(payloadInput);
            var col = readVarInt(payloadInput);
            var fileIdx = readVarInt(payloadInput) - 1;
            var file = (fileIdx >= 0 && fileIdx < stringPool.length) ? stringPool[fileIdx] : null;
            var pos:haxiom.AST.Pos = (line == 0 && col == 0 && fileIdx == -1) ? null : { line: line, col: col, file: file };
            for (j in 0...count) {
                positions.push(pos);
            }
        }
        
        // 4. Read constants
        var constsLen = readVarInt(payloadInput);
        var constsStr = payloadInput.readString(constsLen);
        var constants:Array<Dynamic> = haxe.Unserializer.run(constsStr);
        for (i in 0...constants.length) {
            var c = constants[i];
            if (c != null && Std.isOfType(c, BinaryExprHolder)) {
                var holder:BinaryExprHolder = cast c;
                constants[i] = BinaryASTSerializer.deserialize(holder.bytes);
            }
        }
        
        // 5. Read debug symbols
        var debugSymLength = readVarInt(payloadInput);
        var debugSymbols:Array<DebugSymbol> = null;
        if (debugSymLength > 0) {
            debugSymbols = [for (i in 0...debugSymLength) {
                var nameIdx = readVarInt(payloadInput);
                var slot = readVarInt(payloadInput);
                var startIp = readVarInt(payloadInput);
                var endIp = readVarInt(payloadInput);
                var name = (nameIdx >= 0 && nameIdx < stringPool.length) ? stringPool[nameIdx] : "";
                var sym:DebugSymbol = { name: name, slot: slot, startIp: startIp, endIp: endIp };
                sym;
            }];
        }

        var chunk = new BytecodeChunk(instructions, constants, positions, maxSlots, isAsync, debugSymbols);
        BytecodeVerifier.verify(chunk);
        return chunk;
    }
}
