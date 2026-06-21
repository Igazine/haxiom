package haxiom;

import haxe.Constraints.IMap;
import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;

class DynamicMap implements IMap<Dynamic, Dynamic> {
    public var stringMap:StringMap<Dynamic>;
    public var intMap:IntMap<Dynamic>;
    public var objectMap:ObjectMap<Dynamic, Dynamic>;

    public function new() {}

    public function get(k:Dynamic):Dynamic {
        #if haxiom_debug
        trace("DynamicMap.get key=" + Std.string(k) + " type=" + Std.string(Type.typeof(k)) + " isString=" + TypeSystem.isString(k) + " isInt=" + TypeSystem.isInt(k));
        #end
        if (TypeSystem.isString(k)) {
            return stringMap != null ? stringMap.get(k) : null;
        } else if (TypeSystem.isInt(k)) {
            return intMap != null ? intMap.get(k) : null;
        } else {
            return objectMap != null ? objectMap.get(k) : null;
        }
    }

    public function set(k:Dynamic, v:Dynamic):Void {
        #if haxiom_debug
        trace("DynamicMap.set key=" + Std.string(k) + " value=" + Std.string(v) + " type=" + Std.string(Type.typeof(k)) + " isString=" + TypeSystem.isString(k) + " isInt=" + TypeSystem.isInt(k));
        #end
        if (TypeSystem.isString(k)) {
            if (stringMap == null) stringMap = new StringMap<Dynamic>();
            stringMap.set(k, v);
        } else if (TypeSystem.isInt(k)) {
            if (intMap == null) intMap = new IntMap<Dynamic>();
            intMap.set(k, v);
        } else {
            if (objectMap == null) objectMap = new ObjectMap<Dynamic, Dynamic>();
            objectMap.set(k, v);
        }
    }

    public function exists(k:Dynamic):Bool {
        if (TypeSystem.isString(k)) {
            return stringMap != null && stringMap.exists(k);
        } else if (TypeSystem.isInt(k)) {
            return intMap != null && intMap.exists(k);
        } else {
            return objectMap != null && objectMap.exists(k);
        }
    }

    public function remove(k:Dynamic):Bool {
        if (TypeSystem.isString(k)) {
            return stringMap != null && stringMap.remove(k);
        } else if (TypeSystem.isInt(k)) {
            return intMap != null && intMap.remove(k);
        } else {
            return objectMap != null && objectMap.remove(k);
        }
    }

    public function keys():Iterator<Dynamic> {
        var arr:Array<Dynamic> = [];
        if (stringMap != null) for (k in stringMap.keys()) arr.push(k);
        if (intMap != null) for (k in intMap.keys()) arr.push(k);
        if (objectMap != null) for (k in objectMap.keys()) arr.push(k);
        return arr.iterator();
    }

    public function iterator():Iterator<Dynamic> {
        var arr:Array<Dynamic> = [];
        if (stringMap != null) for (v in stringMap.iterator()) arr.push(v);
        if (intMap != null) for (v in intMap.iterator()) arr.push(v);
        if (objectMap != null) for (v in objectMap.iterator()) arr.push(v);
        return arr.iterator();
    }

    public function keyValueIterator():KeyValueIterator<Dynamic, Dynamic> {
        var arr:Array<{key:Dynamic, value:Dynamic}> = [];
        if (stringMap != null) for (k in stringMap.keys()) arr.push({ key: k, value: stringMap.get(k) });
        if (intMap != null) for (k in intMap.keys()) arr.push({ key: k, value: intMap.get(k) });
        if (objectMap != null) for (k in objectMap.keys()) arr.push({ key: k, value: objectMap.get(k) });
        return cast arr.iterator();
    }

    public function copy():DynamicMap {
        var c = new DynamicMap();
        if (stringMap != null) c.stringMap = stringMap.copy();
        if (intMap != null) c.intMap = intMap.copy();
        if (objectMap != null) c.objectMap = objectMap.copy();
        return c;
    }

    public function toString():String {
        var parts = [];
        if (stringMap != null) parts.push(stringMap.toString());
        if (intMap != null) parts.push(intMap.toString());
        if (objectMap != null) parts.push(objectMap.toString());
        return "{" + parts.join(", ") + "}";
    }

    public function clear():Void {
        stringMap = null;
        intMap = null;
        objectMap = null;
    }
}
