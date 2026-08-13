package plugins.example;

import interfaces.IPlugin;

class Plugin implements IPlugin {
	public var pluginName(get, never):String;
	public var counter(get, set):Int;

	public function new() {
		trace("Plugin created");
		counter = 0;
	}

	function get_pluginName():String return "typed-plugin";
	function get_counter():Int return counter;
	function set_counter(value:Int):Int return counter = value;

	public function doSomething():Void {
		trace("Doing something");
	}

	public function calc(a:Int, b:Int):Int {
		return a + b;
	}
}
