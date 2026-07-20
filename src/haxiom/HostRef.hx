package haxiom;

import haxiom.Interp;

/**
 * An un-spoofable, opaque host reference handle for guest scripts.
 * Stores underlying host objects ONLY in host-private memory.
 * All methods are strictly static to guarantee zero script instance fields or methods.
 */
@:keep
final class HostRef<T> {
	// Private host-side registry: HostRef handle instance -> host object + interp memory tracker
	private static var registry:Map<HostRef<Dynamic>, {value:Dynamic, interp:Null<Interp>}> = new Map();

	// Private constructor — Guest scripts CANNOT call 'new HostRef()'
	private function new() {}

	/**
	 * Wraps a native host object into an opaque HostRef handle for guest scripts.
	 * Optionally tracks memory allocation (64 units) against the active Interp safeguard.
	 */
	public static function wrap<T>(value:T, ?interp:Interp):HostRef<T> {
		if (value == null)
			return null;
		if (interp != null) {
			interp.trackMemory(64);
		}
		var ref = new HostRef<T>();
		registry.set(ref, {value: value, interp: interp});
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
		if (!registry.exists(hostRef)) {
			return null; // Unrecognized / spoofed handle -> Rejected!
		}

		var data = registry.get(hostRef);
		return data != null ? cast data.value : null;
	}

	/**
	 * Frees and invalidates a HostRef handle from host memory.
	 * Also releases the memory allocation tracking on the Interp safeguard.
	 */
	public static function free(ref:Dynamic):Void {
		if (ref != null && Type.getClass(ref) == HostRef) {
			var hostRef:HostRef<Dynamic> = cast ref;
			if (registry.exists(hostRef)) {
				var data = registry.get(hostRef);
				if (data != null && data.interp != null) {
					data.interp.trackMemory(-64);
				}
				registry.remove(hostRef);
			}
		}
	}
}
