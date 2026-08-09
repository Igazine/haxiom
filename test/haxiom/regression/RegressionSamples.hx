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
				name: "single-statement-anonymous-function",
				moduleName: "SingleStatementAnonymousFunction",
				expected: Value("2|4|6"),
				source: '
					class SingleStatementAnonymousFunction {
						static public function main():String {
							var values = [1, 2, 3];
							var doubled = values.map(function(value) return value * 2);
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
				name: "caught-constructor-exception",
				moduleName: "CaughtConstructorException",
					expected: Value("negative:method:42"),
				source: '
					class FallibleValue {
						var value:Int;

						public function new(value:Int) {
							if (value < 0) {
								throw "negative";
							}
							this.value = value;
						}

						public function read():Int {
							return value;
						}

						public function fail():Void {
							throw "method";
						}
					}

					class CaughtConstructorException {
						static public function main():String {
							var status = "missed";
							try {
								new FallibleValue(-1);
							} catch (error:Dynamic) {
								status = Std.string(error);
							}
							var value = new FallibleValue(42);
							try {
								value.fail();
							} catch (error:Dynamic) {
								status += ":" + Std.string(error);
							}
							return status + ":" + value.read();
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
				name: "parenthesized-type-cast",
				moduleName: "ParenthesizedTypeCast",
				expected: Value("6"),
				source: '
					class ParenthesizedTypeCast {
						static public function main():Int {
							var dynamicValues:Dynamic = [1, 2, 3];
							var total = 0;
							for (value in (dynamicValues:Array<Int>)) {
								total += value;
							}
							return total;
						}
					}
				'
			},
			{
				name: "multiline-additive-expression",
				moduleName: "MultilineAdditiveExpression",
				expected: Value("alpha:42:omega"),
				source: '
					class MultilineAdditiveExpression {
						static public function main():String {
							return "alpha"
								+ ":" + 42
								+ ":omega";
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
				name: "switch-expression",
				moduleName: "SwitchExpression",
				expected: Value("answer"),
				source: '
					class SwitchExpression {
						static public function main():String {
							var value = 42;
							return switch (value) {
								case 0: "zero";
								case 42: "answer";
								default: "other";
							};
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
				name: "qualified-standard-type-path",
				moduleName: "QualifiedStandardTypePath",
				expected: Value("42"),
				source: '
					class QualifiedStandardTypePath {
						static public function main():Int {
							var encoded = haxe.Json.stringify({value: 42});
							var decoded:Dynamic = haxe.Json.parse(encoded);
							return decoded.value;
						}
					}
				'
			},
			{
				name: "json-nested-primitive-values",
				moduleName: "JsonNestedPrimitiveValues",
				expected: Value("Alice|true|7"),
				source: '
					class JsonNestedPrimitiveValues {
						static public function main():String {
							var encoded = haxe.Json.stringify({
								user: {name: "Alice", active: true, score: 7}
							});
							var decoded:Dynamic = haxe.Json.parse(encoded);
							return decoded.user.name + "|" + decoded.user.active + "|" + decoded.user.score;
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
				name: "property-accessor-dce",
				moduleName: "PropertyAccessorDCE",
				expected: Value("42"),
				source: '
					class AccessorValue {
						public var value(default, set):Int;

						public function new() {
							value = 0;
						}

						function set_value(next:Int):Int {
							value = next * 2;
							return value;
						}
					}

					class PropertyAccessorDCE {
						static public function main():Int {
							var item = new AccessorValue();
							item.value = 21;
							return item.value;
						}
					}
				'
			},
			{
				name: "filtered-comprehension-parity",
				moduleName: "FilteredComprehensionParity",
				expected: Value("0,2,4,6,8"),
				source: '
					class FilteredComprehensionParity {
						static public function main():String {
							var values = [for (value in 0...10) if (value % 2 == 0) value];
							return values.join(",");
						}
					}
				'
			},
			{
				name: "guarded-catch-parity",
				moduleName: "GuardedCatchParity",
				expected: Value("code:404"),
				source: '
					enum GuardedCatchFailure {
						Code(value:Int);
						Message(value:String);
					}

					class GuardedCatchParity {
						static public function main():String {
							try {
								throw Code(404);
							} catch (Code(value) if (value >= 400)) {
								return "code:" + value;
							} catch (Message(value)) {
								return "message:" + value;
							}
							return "missed";
						}
					}
				'
			},
			{
				name: "abstract-underlying-parity",
				moduleName: "AbstractUnderlyingParity",
				expected: Value("42:50"),
				source: '
					abstract RegressionScore(Int) {
						public function new(value:Int) {
							this = value;
						}

						public function value():Int {
							return this;
						}
						public var doubled(get, never):Int;
						function get_doubled():Int {
							return this * 2;
						}

						@:op(A + B)
						public static function add(a:RegressionScore, b:RegressionScore):RegressionScore {
							return new RegressionScore(a.value() + b.value());
						}
					}

					class AbstractUnderlyingParity {
						static public function main():String {
							var left = new RegressionScore(21);
							var total = left + new RegressionScore(29);
							return left.doubled + ":" + total.value();
						}
					}
				'
			},
			{
				name: "safe-method-short-circuit",
				moduleName: "SafeMethodShortCircuit",
				expected: Value("null:0"),
				source: '
					class SafeCallTarget {
						public function new() {}
						public function consume(value:Int):Int return value;
					}

					class SafeMethodShortCircuit {
						static var evaluations:Int = 0;

						static function argument():Int {
							evaluations++;
							return 42;
						}

						static public function main():String {
							var target:SafeCallTarget = null;
							var result = target?.consume(argument());
							return Std.string(result) + ":" + evaluations;
						}
					}
				'
			},
			{
				name: "method-specific-access-metadata",
				moduleName: "MethodSpecificAccessMetadata",
				expected: Value("42"),
				source: '
					class AccessMetadataTarget {
						public function new() {}
						function hidden():Int return 42;
					}

					class AccessMetadataReader {
						public function new() {}

						@:access(AccessMetadataTarget.hidden)
						public function read(target:AccessMetadataTarget):Int return target.hidden();
					}

					class MethodSpecificAccessMetadata {
						static public function main():Int {
							return new AccessMetadataReader().read(new AccessMetadataTarget());
						}
					}
				'
			},
			{
				name: "persisted-error-position",
				moduleName: "PersistedErrorPosition",
				expected: RuntimeFailure("persisted-position-failure"),
				debugBytecode: true,
				expectedLine: 4,
				source: 'class PersistedErrorPosition {
					static public function main():Void {
						var marker = 42;
						throw "persisted-position-failure";
					}
				}'
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
