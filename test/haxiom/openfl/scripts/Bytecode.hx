package;

import feathers.controls.*;
import feathers.events.*;

using StringTools;

class Bytecode {
	static public function main() {
		trace("Hello from Bytecode example!");
		var container = ScriptContext.container;
		var text = "     Click me!      ".trim();
		var btn = new Button(text);
		btn.addEventListener(TriggerEvent.TRIGGER, (e:TriggerEvent) -> {
			trace("Button clicked in the pre-compiled Bytecode example!");
			Alert.show("Button clicked in the pre-compiled Bytecode example!", "Info", ["OK"]);
		});
		container.addChild(btn);
		return;

		var asdasd = '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
	}
}

class DCE {
	var n1:Int = 1;
	var n2:Int = 2;
	var thisIsACustomVariableName:String = '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';

	public function new() {
		n1 = 1;
		n2 = 2;
	}

	function foo() {
		return n1 + n2;
	}

	function bar() {
		return foo();
	}
}

#if !haxiom
// Definitions for error-free local compilation, and Language Server Protocol in IDEs
// This block is ignored in Haxiom
class ScriptContext {
	public static var container:LayoutGroup;
}
#end
