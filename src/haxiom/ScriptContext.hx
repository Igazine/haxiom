package haxiom;

/**
 * Immutable per-operation identity and compilation settings for a guest script.
 *
 * `name` is the logical Haxe module name and controls automatic `main()` routing.
 * `sourceLabel` is used in diagnostics and defaults to `name`.
 */
class ScriptContext {
	public final name:Null<String>;
	public final sourceLabel:Null<String>;
	public final packageName:Null<String>;
	public final staticTypes:Bool;

	public function new(?name:String, ?sourceLabel:String, ?packageName:String, ?staticTypes:Bool = false) {
		this.name = name;
		this.sourceLabel = sourceLabel;
		this.packageName = packageName;
		this.staticTypes = staticTypes;
	}
}
