package scenario.initializers;

class StaticInitializerMacroSandbox {
	static var invalid:String = hostSecret.value;

	@:haxiom.macro
	static public function identity(expr:Dynamic):Dynamic {
		return expr;
	}
}
