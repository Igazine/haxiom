package haxiom;

/**
 * Represents a single call frame on the active Haxiom script execution stack.
 */
typedef ScriptStackFrame = {
	var file:String;
	var className:String;
	var methodName:String;
	var line:Int;
	var column:Int;
}
