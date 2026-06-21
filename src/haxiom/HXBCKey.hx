package haxiom;

abstract HXBCKey(String) {
    public inline function new(key:String) {
        this = key;
    }
    
    @:from
    public static inline function fromString(s:String):HXBCKey {
        return new HXBCKey(s);
    }
    
    @:to
    public inline function toString():String {
        return this;
    }
    
    public inline function isValid():Bool {
        return this != null && this.length > 0;
    }
}
