package haxiom.regression;

import haxiom.regression.RegressionExpectation;

class RegressionSamples {
	public static function all():Array<RegressionSample> {
		return [
			{
				name: "arithmetic-loop",
				moduleName: "ArithmeticLoop",
				expected: Value("30"),
				source: '
					class ArithmeticLoop {
						static public function main():Int {
							var total = 0;
							for (i in 0...5) {
								total += i * i;
							}
							return total;
						}
					}
				'
			},
			{
				name: "class-method-state",
				moduleName: "ClassMethodState",
				expected: Value("9"),
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

					class ClassMethodState {
						static public function main():Int {
							var acc = new Accumulator(3);
							return acc.add([1, 2, 3]);
						}
					}
				'
			},
			{
				name: "closures-and-array-methods",
				moduleName: "ClosuresAndArrayMethods",
				expected: Value("4|8"),
				source: '
					class ClosuresAndArrayMethods {
						static public function main():String {
							var values = [1, 2, 3, 4];
							var even = values.filter(function(v) {
								return v % 2 == 0;
							});
							var doubled = even.map(function(v) {
								return v * 2;
							});
							return doubled.join("|");
						}
					}
				'
			},
			{
				name: "try-catch-finally-flow",
				moduleName: "TryCatchFlow",
				expected: Value("caught:done"),
				source: '
					class TryCatchFlow {
						static public function main():String {
							var status = "start";
							try {
								throw "fail";
							} catch (e:Dynamic) {
								status = "caught";
							}
							return status + ":done";
						}
					}
				'
			},
			{
				name: "safe-navigation-and-coalesce",
				moduleName: "SafeNavigationAndCoalesce",
				expected: Value("fallback:42"),
				source: '
					class SafeNavigationAndCoalesce {
						static public function main():String {
							var maybe:Dynamic = null;
							var value = maybe?.field ?? "fallback";
							var payload = { count: 42 };
							return value + ":" + payload?.count;
						}
					}
				'
			},
			{
				name: "inheritance-and-override",
				moduleName: "InheritanceAndOverride",
				expected: Value("base:child"),
				source: '
					class RegressionBase {
						public function new() {}
						public function label():String return "base";
					}

					class RegressionChild extends RegressionBase {
						public function new() super();
						override public function label():String return super.label() + ":child";
					}

					class InheritanceAndOverride {
						static public function main():String {
							var value:RegressionBase = new RegressionChild();
							return value.label();
						}
					}
				'
			},
			{
				name: "enum-pattern-switch",
				moduleName: "EnumPatternSwitch",
				expected: Value("payload:7"),
				source: '
					enum RegressionMessage {
						Empty;
						Payload(value:Int);
					}

					class EnumPatternSwitch {
						static public function main():String {
							var message = Payload(7);
							var result = "";
							switch (message) {
								case Empty: result = "empty";
								case Payload(value): result = "payload:" + value;
							}
							return result;
						}
					}
				'
			},
			{
				name: "regex-literal",
				moduleName: "RegexLiteral",
				expected: Value("true"),
				source: '
					class RegexLiteral {
						static public function main():Bool {
							return ~/haxiom\\s+\\d+/i.match("HAXIOM 42");
						}
					}
				'
			},
			{
				name: "instance-static-isolation",
				moduleName: "InstanceStaticIsolation",
				expected: Value("1"),
				source: '
					class InstanceStaticIsolation {
						static var count:Int = 0;

						static public function main():Int {
							count++;
							return count;
						}
					}
				'
			},
			{
				name: "parser-error",
				moduleName: "ParserError",
				expected: CompileFailure("Unexpected"),
				source: '
					class ParserError {
						static public function main():Int {
							return 1 + ;
						}
					}
				'
			},
			{
				name: "static-type-error",
				moduleName: "StaticTypeError",
				staticTypes: true,
				expected: CompileFailure("Type mismatch"),
				source: '
					class StaticTypeError {
						static public function main():Int {
							var value:Int = "not-an-int";
							return value;
						}
					}
				'
			},
			{
				name: "runtime-error",
				moduleName: "RuntimeError",
				expected: RuntimeFailure("expected-runtime-failure"),
				source: '
					class RuntimeError {
						static public function main():Void {
							throw "expected-runtime-failure";
						}
					}
				'
			}
		];
	}
}
