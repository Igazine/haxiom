package;

import feathers.controls.*;
import feathers.events.*;

using StringTools;

/*
 * Basic UI Demo - Dynamically generated Button, Event Listener, and Alert dialog
 */
class Basic {
	// Static `main()` is automatically called from Haxiom
	static public function main() {
		trace("Hello from Basic.hx!");
		// Retrieving container from host
		var container = ScriptContext.container;
		trace('Main container:' + container);
		var text = "     Click me!      ".trim();
		var btn = new Button(text);
		btn.addEventListener(TriggerEvent.TRIGGER, (e:TriggerEvent) -> {
			trace("Button clicked!");
			Alert.show("Button clicked!", "Info", ["OK"]);
		});
		container.addChild(btn);
	}
}

#if !haxiom_script
/*
 * Definitions for error-free local compilation, and Language Server Protocol in IDEs
 * This block is ignored in Haxiom
 */
class ScriptContext {
	public static var container:LayoutGroup;
}
#end
