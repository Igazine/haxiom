package haxiom.guest;

/**
 * Guest-facing engine helper class.
 * This class is the primary entry point for built-in operations inside Haxiom guest scripts.
 */
class HaxiomHost {
	private function new() {}

	/**
	 * Suspends execution of the current cooperative fiber until the promise/future resolves.
	 * 
	 * Note: Can only be used inside Haxiom guest scripts running in VM mode.
	 */
	public static function await<T>(future:Future<T>):T {
		throw "HaxiomHost.await() can only be used inside Haxiom guest scripts executing in the VM.";
	}

	/**
	 * Registers a cleanup callback to be executed when this Haxiom engine instance is disposed.
	 * Use this to unregister global host event listeners, timers, or native resources.
	 */
	public static function onDispose(callback:Void->Void):Void {
		throw "HaxiomHost.onDispose() can only be used inside Haxiom guest scripts executing in the VM or AST.";
	}
}
