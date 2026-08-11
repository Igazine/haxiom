package scenario.initializers;

class StaticInitializerScenario {
	static var events:Array<String> = [];
	static var first:Int = initializeFirst();
	static var second:Int = StaticInitializerScenario.initializeSecond();

	static function initializeFirst():Int {
		events.push("first");
		return 41;
	}

	static function initializeSecond():Int {
		events.push("second");
		return first + 1;
	}

	static public function main():String {
		return first + "|" + second + "|" + events.join(",") + "|" + events.length;
	}
}
