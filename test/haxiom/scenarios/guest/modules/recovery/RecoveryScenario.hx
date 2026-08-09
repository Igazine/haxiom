package scenario.modules.recovery;

import scenario.modules.recovery.RecoveryDependency;

class RecoveryScenario {
	static public function main():String {
		var first = RecoveryDependency.evaluate(1);
		var second = RecoveryDependency.evaluate(2);
		return first + "|" + second + "|" + RecoveryDependency.evaluationCount();
	}
}
