package haxiom.regression;

class RegressionSamples {
	public static function all():Array<RegressionSample> {
		return [
			{
				name: "arithmetic-loop",
				expected: "30",
				source: '
					var total = 0;
					for (i in 0...5) {
						total += i * i;
					}
					total;
				'
			},
			{
				name: "class-method-state",
				expected: "9",
				source: '
					class Accumulator {
						public var base:Int;

						public function new(base:Int) {
							this.base = base;
						}

						public function add(values:Array<Int>):Int {
							var total = base;
							for (v in values) {
								total += v;
							}
							return total;
						}
					}

					var acc = new Accumulator(3);
					acc.add([1, 2, 3]);
				'
			},
			{
				name: "closures-and-array-methods",
				expected: "4|8",
				source: '
					var values = [1, 2, 3, 4];
					var even = values.filter(function(v) {
						return v % 2 == 0;
					});
					var doubled = even.map(function(v) {
						return v * 2;
					});
					doubled.join("|");
				'
			},
			{
				name: "try-catch-finally-flow",
				expected: "caught:done",
				source: '
					var status = "start";
					try {
						throw "fail";
					} catch (e:Dynamic) {
						status = "caught";
					}
					status + ":done";
				'
			},
			{
				name: "safe-navigation-and-coalesce",
				expected: "fallback:42",
				source: '
					var maybe:Dynamic = null;
					var value = maybe?.field ?? "fallback";
					var payload = { count: 42 };
					value + ":" + payload?.count;
				'
			}
		];
	}
}
