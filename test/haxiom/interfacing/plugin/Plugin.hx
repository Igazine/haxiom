import interfaces.IPlugin;

class Plugin implements IPlugin {
	public function new() {
		trace("Plugin created");
	}

	public function doSomething():Void {
		trace("Doing something");
	}

	public function calc(a:Int, b:Int):Int {
		return a + b;
	}
}
