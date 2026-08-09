package haxiom.scenarios;

private enum ModulePath {
	ASTInterpret;
	VMInterpret;
	ASTBytes;
	RawHXBC;
	CompressedHXBC;
	KeyedCompressedHXBC;
}

private typedef PreparedModuleRun = {
	var execute:Void->Dynamic;
}

class ModuleRecoveryTests {
	static final PATHS = [ASTInterpret, VMInterpret, ASTBytes, RawHXBC, CompressedHXBC, KeyedCompressedHXBC];
	static final BYTECODE_KEY = "haxiom-module-recovery-key";

	public static function runTests():Void {
		trace("Module Failure Recovery Suite");
		trace("-----------------------------");
		for (path in PATHS) {
			var label = pathLabel(path);
			trace('CASE: failed module retry / $label');
			testFailedModuleRetry(path);
			trace('CASE: cyclic module rejection / $label');
			testCyclicModuleRejection(path);
		}
		trace("ALL MODULE FAILURE RECOVERY TESTS PASSED.");
	}

	static function testFailedModuleRetry(path:ModulePath):Void {
		var state = {serveBroken: true, dependencyLoads: 0, leafLoads: 0};
		var engine = new Haxiom();
		engine.moduleResolver = modulePath -> switch (modulePath) {
			case "scenario.modules.recovery.RecoveryDependency":
				state.dependencyLoads++;
				resource(state.serveBroken ? "haxiom.scenario.recovery.dependency.broken" : "haxiom.scenario.recovery.dependency.fixed");
			case "scenario.modules.recovery.RecoveryLeaf":
				state.leafLoads++;
				resource("haxiom.scenario.recovery.leaf");
			default: null;
		};

		var source = resource("haxiom.scenario.recovery.entry");
		var run = prepare(path, engine, source, "RecoveryScenario");
		expectFailure(run.execute, "dependency initialization failed");

		state.serveBroken = false;
		var actual = Std.string(run.execute());
		if (actual != "42|43|2")
			throw 'failed module retry via ${pathLabel(path)} returned $actual';
		if (state.dependencyLoads != 2)
			throw 'failed dependency was cached via ${pathLabel(path)}: resolver count ${state.dependencyLoads}';
		if (state.leafLoads != 1)
			throw 'nested dependency load count via ${pathLabel(path)} was ${state.leafLoads}, expected 1';
	}

	static function testCyclicModuleRejection(path:ModulePath):Void {
		var loadsA = 0;
		var loadsB = 0;
		var serveCycle = true;
		var engine = new Haxiom();
		engine.moduleResolver = modulePath -> switch (modulePath) {
			case "scenario.modules.cycle.CycleA":
				loadsA++;
				resource(serveCycle ? "haxiom.scenario.cycle.a" : "haxiom.scenario.cycle.a.fixed");
			case "scenario.modules.cycle.CycleB":
				loadsB++;
				resource("haxiom.scenario.cycle.b");
			default: null;
		};

		var source = resource("haxiom.scenario.cycle.entry");
		var run = prepare(path, engine, source, "CycleScenario");
		expectFailure(run.execute, "Cyclic module import:");
		serveCycle = false;
		var actual = Std.string(run.execute());
		if (actual != "7")
			throw 'cycle recovery via ${pathLabel(path)} returned $actual';
		if (loadsA != 2 || loadsB != 1)
			throw 'cyclic resolver counts via ${pathLabel(path)} were A=$loadsA, B=$loadsB';
	}

	static function prepare(path:ModulePath, engine:Haxiom, source:String, moduleName:String):PreparedModuleRun {
		var context = new ScriptContext(moduleName, 'test/scenarios/$moduleName.hx');
		return switch (path) {
			case ASTInterpret | VMInterpret:
				engine.useVM = path == VMInterpret;
				{execute: () -> engine.interpret(source, context)};
			case ASTBytes:
				var bytes = compilationEngine().compileToASTBytes(source, context);
				{execute: () -> engine.executeASTBytes(bytes, source)};
			case RawHXBC | CompressedHXBC | KeyedCompressedHXBC:
				var keyed = path == KeyedCompressedHXBC;
				var key = keyed ? BYTECODE_KEY : null;
				var bytes = compilationEngine().compileToBytecodeBytes(source, context, key, true, path != RawHXBC);
				{execute: () -> engine.executeBytecodeBytes(bytes, source, key)};
		};
	}

	static function compilationEngine():Haxiom {
		var engine = new Haxiom();
		engine.moduleResolver = modulePath -> switch (modulePath) {
			case "scenario.modules.recovery.RecoveryDependency": resource("haxiom.scenario.recovery.dependency.fixed");
			case "scenario.modules.recovery.RecoveryLeaf": resource("haxiom.scenario.recovery.leaf");
			case "scenario.modules.cycle.CycleA": resource("haxiom.scenario.cycle.a.fixed");
			case "scenario.modules.cycle.CycleB": resource("haxiom.scenario.cycle.b");
			default: null;
		};
		return engine;
	}

	static function expectFailure(action:Void->Dynamic, messagePart:String):Void {
		var caught:Dynamic = null;
		try {
			action();
		} catch (error:Dynamic) {
			caught = error;
		}
		if (caught == null)
			throw 'Expected module failure containing "$messagePart"';
		if (Std.string(caught).indexOf(messagePart) == -1)
			throw 'Module failure did not contain "$messagePart": ${Std.string(caught)}';
	}

	static function resource(name:String):String {
		var value = haxe.Resource.getString(name);
		if (value == null)
			throw 'Missing bundled module test resource: $name';
		return value;
	}

	static function pathLabel(path:ModulePath):String {
		return switch (path) {
			case ASTInterpret: "AST interpret";
			case VMInterpret: "VM interpret";
			case ASTBytes: "AST bytes";
			case RawHXBC: "raw HXBC";
			case CompressedHXBC: "compressed HXBC";
			case KeyedCompressedHXBC: "keyed compressed HXBC";
		};
	}
}
