package haxiom.scenarios;

class ScenarioHostPricing {
	public static function discountRate(tier:String, total:Int):Int {
		if (tier == "gold" && total >= 6000)
			return 15;
		if (tier == "silver")
			return 5;
		return 0;
	}

	public static function shippingFor(total:Int):Int {
		return total >= 5000 ? 0 : 450;
	}
}
