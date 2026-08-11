package scenario.initializers;

class InvalidStaticInitializer {
	function compute():Int return 42;
	static var invalid:Int = compute();
}
