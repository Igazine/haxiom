package scenario.modules.pricing;

class PricingRules {
	static var evaluations:Int = 0;

	public static function quote(plan:String, seats:Int):Int {
		evaluations++;
		var base = switch (plan) {
			case "starter": 1000;
			case "enterprise": 3000;
			default: throw "unknown plan";
		};
		return base + seats * 50;
	}

	public static function evaluationCount():Int {
		return evaluations;
	}
}
