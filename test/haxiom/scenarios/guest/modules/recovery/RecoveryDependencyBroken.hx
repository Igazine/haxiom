package scenario.modules.recovery;

class BrokenDependencyBoot {
	public function new() {
		throw "dependency initialization failed";
	}
}

class RecoveryDependency {
	public static var bootValue:BrokenDependencyBoot = new BrokenDependencyBoot();

	public static function evaluate(offset:Int):Int {
		return offset;
	}

	public static function evaluationCount():Int {
		return 0;
	}
}
