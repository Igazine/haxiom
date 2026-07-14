package haxiom;

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
	public static function await<T>(future:Dynamic):T {
		throw "HaxiomHost.await() can only be used inside Haxiom guest scripts executing in the VM.";
	}
}
