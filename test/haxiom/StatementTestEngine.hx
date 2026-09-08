package haxiom;

/** Legacy instruction-level fixtures are statement lists, not public script modules.
 * Application scenarios and public API tests must use Haxiom directly.
 */
class StatementTestEngine extends Haxiom {
	public function new() {
		super();
	}

	override public function compile(source:String, ?context:ScriptContext):haxiom.AST.Expr {
		return compileInternal(source, context, false);
	}
}
