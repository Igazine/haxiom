package haxiom;

import haxiom.regression.RegressionSample;
import haxiom.regression.RegressionSamples;

class TestRegressionSamples {
	public static function main():Void {
		runTests();
	}

	public static function runTests():Void {
		trace("Regression Sample Suite");
		trace("-----------------------");

		var passed = 0;
		for (sample in RegressionSamples.all()) {
			runSample(sample);
			passed++;
			trace('SUCCESS: ${sample.name}');
		}

		trace('ALL REGRESSION SAMPLES PASSED ($passed samples).');
	}

	static function runSample(sample:RegressionSample):Void {
		assertResult(sample, "AST interpret", () -> {
			var h = new Haxiom();
			h.useVM = false;
			return h.interpret(sample.source, null);
		});

		assertResult(sample, "VM interpret", () -> {
			var h = new Haxiom();
			h.useVM = true;
			return h.interpret(sample.source, null);
		});

		assertResult(sample, "AST bytes", () -> {
			var h = new Haxiom();
			var bytes = h.compileToASTBytes(sample.source, new ScriptContext(sample.name, sample.name + ".hx"));
			var runner = new Haxiom();
			return runner.executeASTBytes(bytes, sample.source);
		});

		assertResult(sample, "HXBC bytes", () -> {
			var h = new Haxiom();
			var bytes = h.compileToBytecodeBytes(sample.source, new ScriptContext(sample.name, sample.name + ".hx"), null, false, false);
			var runner = new Haxiom();
			return runner.executeBytecodeBytes(bytes, sample.source);
		});

		assertResult(sample, "compressed HXBC bytes", () -> {
			var h = new Haxiom();
			var bytes = h.compileToBytecodeBytes(sample.source, new ScriptContext(sample.name, sample.name + ".hx"), null, false, true);
			var runner = new Haxiom();
			return runner.executeBytecodeBytes(bytes, sample.source);
		});
	}

	static function assertResult(sample:RegressionSample, path:String, run:Void->Dynamic):Void {
		var result = run();
		var actual = Std.string(result);
		if (actual != sample.expected) {
			throw '${sample.name} failed via $path: expected ${sample.expected}, got $actual';
		}
	}
}
