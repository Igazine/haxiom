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

	public function mutateBytes(value:haxe.io.Bytes):haxe.io.Bytes {
		value.set(0, value.get(0) + 1);
		return value;
	}

	public function mutateNumbers(values:Array<Int>):Array<Int> {
		values[0] = values[0] + 1;
		return values;
	}

	public function updatePayload(payload:{name:String, count:Int}):{name:String, count:Int} {
		payload.count = payload.count + 1;
		return payload;
	}

	public function leakGuestValue():Dynamic {
		return new GuestValue();
	}
}

class GuestValue {
	public function new() {}
}
