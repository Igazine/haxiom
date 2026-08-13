interface IPlugin {
	public var pluginName(get, never):String;
	public var counter(get, set):Int;
	public function doSomething():Void;
	public function calc(a:Int, b:Int):Int;
	public function mutateBytes(value:haxe.io.Bytes):haxe.io.Bytes;
	public function mutateNumbers(values:Array<Int>):Array<Int>;
	public function updatePayload(payload:{name:String, count:Int}):{name:String, count:Int};
	public function leakGuestValue():Dynamic;
}

class SpoofedInterfacePlugin implements IPlugin {
	public var pluginName(get, never):String;
	public var counter(get, set):Int;

	public function new() {
		counter = 0;
	}

	function get_pluginName():String return "spoofed";
	function get_counter():Int return counter;
	function set_counter(value:Int):Int return counter = value;
	public function doSomething():Void {}
	public function calc(a:Int, b:Int):Int return a + b;
	public function mutateBytes(value:haxe.io.Bytes):haxe.io.Bytes return value;
	public function mutateNumbers(values:Array<Int>):Array<Int> return values;
	public function updatePayload(payload:{name:String, count:Int}):{name:String, count:Int} return payload;
	public function leakGuestValue():Dynamic return null;
}
