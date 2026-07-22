package haxiom;

/**
 * An un-spoofable, opaque host reference handle for guest scripts.
 * Stores underlying host objects ONLY in private instance memory.
 * All public methods are strictly static to guarantee zero public script fields or methods.
 */
@:keep
final class HostRef<T> {
	@:noCompletion private var target:Dynamic;

	private function new(target:Dynamic) {
		this.target = target;
	}

	/**
	 * Wraps a native host object into an opaque HostRef handle for guest scripts.
	 */
	public static function wrap<T>(value:T):HostRef<T> {
		if (value == null)
			return null;
		return new HostRef<T>(value);
	}

	/**
	 * Safely unwraps any untrusted reference passed from a guest script.
	 * Returns null if ref is null, spoofed by a script, subclassed, or freed.
	 */
	public static function unwrap<T>(ref:Dynamic):Null<T> {
		if (ref == null)
			return null;

		// Prohibit subclassing or altered class identity
		if (Type.getClass(ref) != HostRef) {
			return null;
		}

		var hostRef:HostRef<Dynamic> = cast ref;
		return hostRef.target;
	}

	/**
	 * Frees and invalidates a HostRef handle from host memory.
	 */
	public static function free(ref:Dynamic):Void {
		if (ref != null && Type.getClass(ref) == HostRef) {
			var hostRef:HostRef<Dynamic> = cast ref;
			hostRef.target = null;
		}
	}
}
