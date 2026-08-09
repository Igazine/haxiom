package scenario.modules.cycle;

import scenario.modules.cycle.CycleA;

class CycleB {
	public static function value():Int {
		return CycleA.value();
	}
}
