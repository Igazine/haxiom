package haxiom;

class CompileException extends haxe.Exception {
    public var line(default, null):Int;
    public var col(default, null):Int;
    public var file(default, null):String;

    public function new(message:String, line:Int = 1, col:Int = 1, ?file:String) {
        super(message);
        this.line = line;
        this.col = col;
        this.file = file != null ? file : "script";
    }
}
