package scenario.initializers;

class StaticInitializerInstructionLimit {
	static var invalid:Int = exhaustBudget();

	static function exhaustBudget():Int {
		while (true) {}
		return 0;
	}

	static public function main():Int {
		return invalid;
	}
}
