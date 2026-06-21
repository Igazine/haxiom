package;

import feathers.controls.Button;

/**
	This script demonstrates basic sandboxing for the Haxiom scripting engine.
	By interfacing between host and script, we can share resources and objects
	without exposing the host's internal implementation details. This is useful
	for security and stability, as it prevents scripts from accessing sensitive
	data or modifying internal state.
**/
class Sandboxing {
	static public function main() {
		trace("Hello from Sandboxing.hx!");
		var container = ScriptContext.sandboxedContainer;
		var btn = new Button("Click me for a Sandboxing example!");
		btn.addEventListener(TriggerEvent.TRIGGER, (e:TriggerEvent) -> {
			trace("The parent of this container is: " + container.parent);
			// This prints `null` because the `container` object we're accessing here
			// is a "proxy" or "wrapper" object, not the actual host object.
			// To access the host object's properties, we would need to pass the actual object
			// from the host to the script.
			Alert.show("The parent of this container is: " + container.parent, "Info", ["OK"]);
			// This line throws a runtime error because `container.parent` is `null`, basically
			// ensuring that the script cannot break out of its sandbox, cannot access parent
			// objects, or even the main stage
			// Check the console for the error message.
			container.parent.removeChild(container);
		});
		container.addChild(btn);
	}
}

#if !haxiom
/*
 * Definitions for error-free local compilation, and Language Server Protocol in IDEs
 * This block is ignored in Haxiom
 */
interface ILayoutGroup {
	function addChild(child:feathers.core.FeathersControl):Void;
}

class ScriptContext {
	public static var sandboxedContainer:ILayoutGroup;
	// Alternative definition without interface
	// public static var sandboxedContainer:{addChild:feathers.core.FeathersControl->Void};
}
#end
