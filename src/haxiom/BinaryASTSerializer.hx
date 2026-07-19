package haxiom;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

class BinaryASTSerializer {
    
    public static function serialize(val:Dynamic):Bytes {
        var stringPool:Array<String> = [];
        var stringMap = new Map<String, Int>();
        
        // Phase 1: collect all strings
        collectStrings(val, stringPool, stringMap);
        
        // Phase 2: serialize to bytes
        var out = new BytesOutput();
        out.bigEndian = false;
        
        // Write string pool
        writeVarInt(out, stringPool.length);
        for (str in stringPool) {
            var sBytes = Bytes.ofString(str);
            writeVarInt(out, sBytes.length);
            out.write(sBytes);
        }
        
        // Serialize object
        serializeValue(val, out, stringMap);
        
        return out.getBytes();
    }
    
    public static function deserialize(bytes:Bytes):Dynamic {
        var input = new BytesInput(bytes);
        input.bigEndian = false;
        
        // Read string pool
        var poolLen = readVarInt(input);
        var stringPool = [for (i in 0...poolLen) {
            var len = readVarInt(input);
            input.readString(len);
        }];
        
        // Deserialize value
        return deserializeValue(input, stringPool);
    }
    
    static function collectStrings(val:Dynamic, pool:Array<String>, map:Map<String, Int>) {
        if (val == null) return;
        
        if (Std.isOfType(val, String)) {
            var s:String = val;
            if (!map.exists(s)) {
                map.set(s, pool.length);
                pool.push(s);
            }
            return;
        }
        
        if (Reflect.isEnumValue(val)) {
            var enumVal:Dynamic = val;
            var e = Type.getEnum(enumVal);
            var enumName = Type.getEnumName(e);
            if (!map.exists(enumName)) {
                map.set(enumName, pool.length);
                pool.push(enumName);
            }
            var constr = Type.enumConstructor(enumVal);
            if (!map.exists(constr)) {
                map.set(constr, pool.length);
                pool.push(constr);
            }
            var params = Type.enumParameters(enumVal);
            for (p in params) {
                collectStrings(p, pool, map);
            }
            return;
        }
        
        if (Std.isOfType(val, Array)) {
            var arr:Array<Dynamic> = val;
            for (item in arr) {
                collectStrings(item, pool, map);
            }
            return;
        }
        
        if (Reflect.isObject(val) && !Std.isOfType(val, Bytes) && !Std.isOfType(val, BinaryExprHolder)) {
            var cls = Type.getClass(val);
            if (cls != null && cls == haxiom.VM.BytecodeChunk) {
                // For BytecodeChunk, we don't traverse its inner properties as we serialize it to binary bytes.
                return;
            }
            var fields = Reflect.fields(val);
            for (f in fields) {
                if (!map.exists(f)) {
                    map.set(f, pool.length);
                    pool.push(f);
                }
                collectStrings(Reflect.field(val, f), pool, map);
            }
            return;
        }
    }
    
    static function encodeZigZag(v:Int):Int {
        return (v << 1) ^ (v >> 31);
    }

    static function decodeZigZag(v:Int):Int {
        return (v >>> 1) ^ -(v & 1);
    }
    
    static function writeVarInt(out:BytesOutput, v:Int) {
        var u = v;
        while (true) {
            if ((u & ~0x7F) == 0) {
                out.writeByte(u & 0x7F);
                break;
            } else {
                out.writeByte((u & 0x7F) | 0x80);
                u = u >>> 7;
            }
        }
    }
    
    static function readVarInt(input:BytesInput):Int {
        var result = 0;
        var shift = 0;
        while (true) {
            var b = input.readByte();
            result |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) {
                break;
            }
            shift += 7;
        }
        return result;
    }
    
    static function serializeValue(val:Dynamic, out:BytesOutput, stringMap:Map<String, Int>) {
        if (val == null) {
            out.writeByte(0);
            return;
        }
        
        if (Std.isOfType(val, Bool)) {
            out.writeByte(1);
            out.writeByte(val ? 1 : 0);
            return;
        }
        
        if (Std.isOfType(val, Int)) {
            out.writeByte(2);
            var zigzag = encodeZigZag(val);
            writeVarInt(out, zigzag);
            return;
        }
        
        if (Std.isOfType(val, Float)) {
            out.writeByte(3);
            out.writeDouble(val);
            return;
        }
        
        if (Std.isOfType(val, String)) {
            out.writeByte(4);
            var idx = stringMap.get(val);
            writeVarInt(out, idx);
            return;
        }
        
        if (Std.isOfType(val, Array)) {
            out.writeByte(5);
            var arr:Array<Dynamic> = val;
            writeVarInt(out, arr.length);
            for (item in arr) {
                serializeValue(item, out, stringMap);
            }
            return;
        }
        
        if (Reflect.isEnumValue(val)) {
            out.writeByte(6);
            var enumVal:Dynamic = val;
            var e = Type.getEnum(enumVal);
            var enumName = Type.getEnumName(e);
            var constr = Type.enumConstructor(enumVal);
            var params = Type.enumParameters(enumVal);
            
            writeVarInt(out, stringMap.get(enumName));
            writeVarInt(out, stringMap.get(constr));
            writeVarInt(out, params.length);
            for (p in params) {
                serializeValue(p, out, stringMap);
            }
            return;
        }
        
        if (Std.isOfType(val, Bytes)) {
            out.writeByte(9);
            var bVal:Bytes = cast val;
            writeVarInt(out, bVal.length);
            out.write(bVal);
            return;
        }
        
        if (Reflect.isObject(val)) {
            var cls = Type.getClass(val);
            if (cls != null && cls == haxiom.VM.BytecodeChunk) {
                out.writeByte(8);
                var bcBytes = Serializer.serializeBytecode(cast val);
                writeVarInt(out, bcBytes.length);
                out.write(bcBytes);
                return;
            }
            
            out.writeByte(7);
            var fields = Reflect.fields(val);
            writeVarInt(out, fields.length);
            for (f in fields) {
                writeVarInt(out, stringMap.get(f));
                serializeValue(Reflect.field(val, f), out, stringMap);
            }
            return;
        }
        
        throw "Unsupported type for serialization: " + Type.getClassName(Type.getClass(val));
    }
    
    static function deserializeValue(input:BytesInput, stringPool:Array<String>):Dynamic {
        var typeTag = input.readByte();
        switch (typeTag) {
            case 0:
                return null;
            case 1:
                return input.readByte() == 1;
            case 2:
                var zigzag = readVarInt(input);
                return decodeZigZag(zigzag);
            case 3:
                return input.readDouble();
            case 4:
                var idx = readVarInt(input);
                return stringPool[idx];
            case 5:
                var len = readVarInt(input);
                var arr = [];
                for (i in 0...len) {
                    arr.push(deserializeValue(input, stringPool));
                }
                return arr;
            case 6:
                var enumNameIdx = readVarInt(input);
                var constrIdx = readVarInt(input);
                var paramLen = readVarInt(input);
                var params = [];
                for (i in 0...paramLen) {
                    params.push(deserializeValue(input, stringPool));
                }
                var enumName = stringPool[enumNameIdx];
                var constr = stringPool[constrIdx];
                var e = Type.resolveEnum(enumName);
                if (e == null) throw 'Enum not found: $enumName';
                return Type.createEnum(e, constr, params);
            case 7:
                var fieldLen = readVarInt(input);
                var obj:Dynamic = {};
                for (i in 0...fieldLen) {
                    var fNameIdx = readVarInt(input);
                    var fName = stringPool[fNameIdx];
                    var val = deserializeValue(input, stringPool);
                    Reflect.setField(obj, fName, val);
                }
                return obj;
            case 8:
                var bcLen = readVarInt(input);
                var bcBytes = input.read(bcLen);
                return Serializer.deserializeBytecode(bcBytes);
            case 9:
                var bLen = readVarInt(input);
                return input.read(bLen);
            default:
                throw 'Unknown type tag $typeTag in binary AST deserialization';
        }
    }
}
