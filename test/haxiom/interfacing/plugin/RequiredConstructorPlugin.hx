import interfaces.IPlugin;

class RequiredConstructorPlugin implements IPlugin {
	public var pluginName(get, never):String;
	public var counter(get, set):Int;

	public function new(initialValue:Int) {
		counter = initialValue;
	}

	function get_pluginName():String return "required-constructor";
	function get_counter():Int return counter;
	function set_counter(value:Int):Int return counter = value;
	public function doSomething():Void {}
	public function calc(a:Int, b:Int):Int return a + b;
}
