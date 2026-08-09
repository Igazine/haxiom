package scenario.modules.orders;

import scenario.modules.pricing.PricingRules;

class UnrelatedEntry {
	static public function main():String {
		throw "nonmatching main executed";
	}
}

class ModuleLifecycleScenario {
	static public function main():String {
		var starter = PricingRules.quote("starter", 5);
		var enterprise = PricingRules.quote("enterprise", 13);
		return starter + "|" + enterprise + "|" + PricingRules.evaluationCount();
	}
}
