import interfaces.IPlugin;

class BadSignaturePlugin implements IPlugin {
	public var pluginName(get, never):String;
	public var counter(get, set):Int;

	public function new() {
		counter = 0;
	}

	function get_pluginName():String return "bad-signature";
	function get_counter():Int return counter;
	function set_counter(value:Int):Int return counter = value;
	public function doSomething():Void {}
	public function calc(a:String, b:Int):Int return b;
}
