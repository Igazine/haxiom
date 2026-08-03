package haxiom;

import haxiom.regression.RegressionSample;
import haxiom.regression.RegressionSamples;
import haxiom.regression.RegressionExpectation;

private typedef RegressionRun = {
	var value:Dynamic;
	var compileError:Null<ScriptException>;
	var runtimeError:Null<ScriptException>;
}

class TestRegressionSamples {
	static final PATHS = ["AST interpret", "VM interpret", "AST bytes", "HXBC bytes", "compressed HXBC bytes"];

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
		// A second pass catches mutable state leaking between otherwise isolated engines.
		for (pass in 0...2) {
			for (path in 0...PATHS.length) {
				trace('CASE: ${sample.name} / ${PATHS[path]} / pass ${pass + 1}');
				assertOutcome(sample, PATHS[path], executePath(sample, path));
			}
		}
	}

	static function executePath(sample:RegressionSample, path:Int):RegressionRun {
		var run:RegressionRun = {value: null, compileError: null, runtimeError: null};
		var context = new ScriptContext(sample.moduleName, sourceLabel(sample), null, sample.staticTypes == true);

		switch (path) {
			case 0 | 1:
				var engine = new Haxiom();
				engine.useVM = path == 1;
				configure(engine, sample, run);
				run.value = engine.interpret(sample.source, context);
			case 2:
				var compiler = new Haxiom();
				configure(compiler, sample, run);
				var bytes = compiler.compileToASTBytes(sample.source, context);
				if (bytes != null) {
					var runner = new Haxiom();
					configure(runner, sample, run);
					run.value = runner.executeASTBytes(bytes, sample.source);
				}
			case 3 | 4:
				var compiler = new Haxiom();
				configure(compiler, sample, run);
				var bytes = compiler.compileToBytecodeBytes(sample.source, context, null, false, path == 4);
				if (bytes != null) {
					var runner = new Haxiom();
					configure(runner, sample, run);
					run.value = runner.executeBytecodeBytes(bytes, sample.source);
				}
			default:
				throw 'Unknown regression path: $path';
		}

		return run;
	}

	static function configure(engine:Haxiom, sample:RegressionSample, run:RegressionRun):Void {
		switch (sample.expected) {
			case CompileFailure(_):
				engine.onCompilerError = error -> run.compileError = error;
			case RuntimeFailure(_):
				engine.onRuntimeError = error -> run.runtimeError = error;
			case Value(_):
		}
	}

	static function assertOutcome(sample:RegressionSample, path:String, run:RegressionRun):Void {
		switch (sample.expected) {
			case Value(expected):
				assertNoError(sample, path, run);
				var actual = Std.string(run.value);
				if (actual != expected) {
					throw '${sample.name} failed via $path: expected $expected, got $actual';
				}
			case CompileFailure(messagePart):
				if (run.compileError == null) {
					throw '${sample.name} failed via $path: expected a compiler error';
				}
				if (run.runtimeError != null) {
					throw '${sample.name} failed via $path: compiler failure also triggered a runtime error';
				}
				assertError(sample, path, "compiler", run.compileError, messagePart);
			case RuntimeFailure(messagePart):
				if (run.compileError != null) {
					throw '${sample.name} failed via $path: unexpected compiler error: ${run.compileError.message}';
				}
				if (run.runtimeError == null) {
					throw '${sample.name} failed via $path: expected a runtime error';
				}
				assertError(sample, path, "runtime", run.runtimeError, messagePart);
		}
	}

	static function assertNoError(sample:RegressionSample, path:String, run:RegressionRun):Void {
		if (run.compileError != null) {
			throw '${sample.name} failed via $path with compiler error: ${run.compileError.message}';
		}
		if (run.runtimeError != null) {
			throw '${sample.name} failed via $path with runtime error: ${run.runtimeError.message}';
		}
	}

	static function assertError(sample:RegressionSample, path:String, kind:String, error:ScriptException, messagePart:String):Void {
		var details = error.message + "\n" + error.formattedStackTrace + "\n" + Std.string(error.rawValue);
		if (details.indexOf(messagePart) == -1) {
			throw '${sample.name} failed via $path: $kind error did not contain "$messagePart": $details';
		}
		if (error.file != sourceLabel(sample)) {
			throw '${sample.name} failed via $path: expected source label ${sourceLabel(sample)}, got ${error.file}';
		}
	}

	static inline function sourceLabel(sample:RegressionSample):String
		return "test/regression/" + sample.moduleName + ".hx";
}
