package haxiom.autofiffi;

class TestClass {
    public var value:Int;
    
    public function new(value:Int) {
        this.value = value;
    }
    
    public function getValue():Int {
        return value;
    }
    
    public static inline var MY_CONSTANT = 999;
}
