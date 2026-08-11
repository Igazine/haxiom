package haxiom.scenarios;

private enum ScenarioPath {
	ASTInterpret;
	VMInterpret;
	ASTBytes;
	RawHXBC;
	CompressedHXBC;
	KeyedCompressedHXBC;
}

class TestScenarios {
	static final PATHS = [ASTInterpret, VMInterpret, ASTBytes, RawHXBC, CompressedHXBC, KeyedCompressedHXBC];
	static final BYTECODE_KEY = "haxiom-scenario-suite-key";

	public static function main():Void {
		trace("Haxiom Application Scenario Suite");
		trace("----------------------------------");

		var passed = 0;
		for (scenario in ScenarioCatalog.all()) {
			runScenario(scenario);
			passed++;
			trace('SUCCESS: ${scenario.name}');
		}
		ModuleRecoveryTests.runTests();
		StaticInitializerTests.runTests();

		trace('ALL APPLICATION SCENARIOS PASSED ($passed scenarios).');
	}

	static function runScenario(scenario:ScenarioDefinition):Void {
		var paths = scenario.vmOnly == true
			? [VMInterpret, RawHXBC, CompressedHXBC, KeyedCompressedHXBC]
			: PATHS;
		for (pass in 0...2) {
			for (path in paths) {
				var label = pathLabel(path);
				trace('CASE: ${scenario.name} / $label / pass ${pass + 1}');
				var actual = execute(scenario, path);
				if (Std.string(actual) != scenario.expected) {
					throw '${scenario.name} failed via $label: expected ${scenario.expected}, got ${Std.string(actual)}';
				}
			}
		}
	}

	static function execute(scenario:ScenarioDefinition, path:ScenarioPath):Dynamic {
		var context = new ScriptContext(scenario.moduleName, sourceLabel(scenario));

		return switch (path) {
			case ASTInterpret | VMInterpret:
				var engine = configuredEngine(scenario);
				engine.useVM = path == VMInterpret;
				engine.interpret(scenario.source, context);
			case ASTBytes:
				var compiler = configuredEngine(scenario);
				var bytes = compiler.compileToASTBytes(scenario.source, context);
				if (bytes == null) {
					throw '${scenario.name} produced null AST bytes';
				}
				configuredEngine(scenario).executeASTBytes(bytes, scenario.source);
			case RawHXBC | CompressedHXBC | KeyedCompressedHXBC:
				var keyed = path == KeyedCompressedHXBC;
				var compressed = path != RawHXBC;
				var key = keyed ? BYTECODE_KEY : null;
				var compiler = configuredEngine(scenario);
				var bytes = compiler.compileToBytecodeBytes(scenario.source, context, key, true, compressed);
				if (bytes == null) {
					throw '${scenario.name} produced null HXBC bytes';
				}
				configuredEngine(scenario).executeBytecodeBytes(bytes, scenario.source, key);
		};
	}

	static function configuredEngine(scenario:ScenarioDefinition):Haxiom {
		var engine = new Haxiom();
		if (scenario.configure != null) {
			scenario.configure(engine);
		}
		return engine;
	}

	static function pathLabel(path:ScenarioPath):String {
		return switch (path) {
			case ASTInterpret: "AST interpret";
			case VMInterpret: "VM interpret";
			case ASTBytes: "AST bytes";
			case RawHXBC: "raw HXBC";
			case CompressedHXBC: "compressed HXBC";
			case KeyedCompressedHXBC: "keyed compressed HXBC";
		};
	}

	static inline function sourceLabel(scenario:ScenarioDefinition):String {
		return "test/scenarios/" + scenario.moduleName + ".hx";
	}
}
