package haxiom.autofiffi;

abstract TestAbstract(Int) {
    public inline function new(v:Int) {
        this = v;
    }
    
    public function getVal():Int {
        return this;
    }
}
