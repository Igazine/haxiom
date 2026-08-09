package scenario.modules.cycle;

import scenario.modules.cycle.CycleB;

class CycleA {
	public static function value():Int {
		return CycleB.value();
	}
}
