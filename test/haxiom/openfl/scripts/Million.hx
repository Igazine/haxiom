package;

import feathers.controls.*;

class Million {
	static public function main() {
		trace("Hello from Million Items example!");
		var a:Array<Int> = [];
		for (i in 0...1000000) {
			a.push(getRandom());
		}
		var container = ScriptContext.container;
		var label = new Label("Compilation and execution have been completed. Check the console for execution time");
		container.addChild(label);
	}

	static function getRandom():Int {
		return Math.floor(Math.random() * 1000000);
	}
}

extern class ScriptContext {
	public static var container:LayoutGroup;
}
