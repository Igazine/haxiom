package haxiom;

/**
 * An un-spoofable, opaque host reference handle for guest scripts.
 * Stores underlying host objects ONLY in host-private memory.
 * All methods are strictly static to guarantee zero script instance fields or methods.
 */
@:keep
final class HostRef<T> {
	// Private host-side registry: HostRef handle instance -> host object
	private static var registry:Map<HostRef<Dynamic>, Dynamic> = new Map();

	// Private constructor — Guest scripts CANNOT call 'new HostRef()'
	private function new() {}

	/**
	 * Wraps a native host object into an opaque HostRef handle for guest scripts.
	 */
	public static function wrap<T>(value:T):HostRef<T> {
		if (value == null)
			return null;
		var ref = new HostRef<T>();
		registry.set(ref, value);
		return ref;
	}

	/**
	 * Safely unwraps any untrusted reference passed from a guest script.
	 * Returns null if ref is null, spoofed by a script, subclassed, or not in host registry.
	 */
	public static function unwrap<T>(ref:Dynamic):Null<T> {
		if (ref == null)
			return null;

		// Prohibit subclassing or altered class identity
		if (Type.getClass(ref) != HostRef) {
			return null;
		}

		var hostRef:HostRef<Dynamic> = cast ref;
		return registry.get(hostRef);
	}

	/**
	 * Frees and invalidates a HostRef handle from host memory.
	 */
	public static function free(ref:Dynamic):Void {
		if (ref != null && Type.getClass(ref) == HostRef) {
			registry.remove(cast ref);
		}
	}
}
