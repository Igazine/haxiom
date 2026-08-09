package scenario.modules.recovery;

import scenario.modules.recovery.RecoveryLeaf;

class RecoveryDependency {
	static var evaluations:Int = 0;
	public static var bootValue:Int = RecoveryLeaf.nextValue();

	public static function evaluate(offset:Int):Int {
		evaluations++;
		return bootValue + offset;
	}

	public static function evaluationCount():Int {
		return evaluations;
	}
}
