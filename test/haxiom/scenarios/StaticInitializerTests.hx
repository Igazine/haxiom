package haxiom.scenarios;

private enum StaticInitializerPath {
	ASTInterpret;
	VMInterpret;
	ASTBytes;
	RawHXBC;
	CompressedHXBC;
	KeyedCompressedHXBC;
}

class StaticInitializerTests {
	static final PATHS = [ASTInterpret, VMInterpret, ASTBytes, RawHXBC, CompressedHXBC, KeyedCompressedHXBC];
	static final BYTECODE_KEY = "haxiom-static-initializer-key";

	public static function runTests():Void {
		trace("Static Initializer Safety Suite");
		trace("-------------------------------");
		testCompileTimeRejections();
		testMacroRegistrationSandbox();
		for (path in PATHS) {
			trace('CASE: initialization semantics / ${pathLabel(path)}');
			testSemantics(path);
			trace('CASE: import sandbox / ${pathLabel(path)}');
			testImportSandbox(path);
			trace('CASE: field filter / ${pathLabel(path)}');
			testFieldFilter(path);
			trace('CASE: instruction limit / ${pathLabel(path)}');
			testInstructionLimit(path);
		}
		trace("ALL STATIC INITIALIZER SAFETY TESTS PASSED.");
	}

	static function testMacroRegistrationSandbox():Void {
		trace("CASE: macro registration sandbox");
		var engine = new Haxiom();
		engine.setGlobal("hostSecret", {value: "classified"});
		engine.setFieldAccessFilter((_, field) -> field != "value");
		expectFailure(() -> engine.compile(resource("haxiom.scenario.initializer.sandbox.macro"),
			new ScriptContext("StaticInitializerMacroSandbox")), "forbidden", "macro registration sandbox");
	}

	static function testCompileTimeRejections():Void {
		var cases = [
			{name: "explicit this", resource: "haxiom.scenario.initializer.invalid.this", message: "Cannot use 'this'"},
			{name: "instance field", resource: "haxiom.scenario.initializer.invalid.field", message: "Cannot access instance member value"},
			{name: "instance method", resource: "haxiom.scenario.initializer.invalid.method", message: "Cannot access instance member compute"},
			{name: "await", resource: "haxiom.scenario.initializer.invalid.await", message: "cannot suspend"}
		];

		for (item in cases) {
			trace('CASE: compile-time rejection / ${item.name}');
			var callbackError:String = null;
			var callbackEngine = new Haxiom();
			callbackEngine.onCompilerError = error -> callbackError = Std.string(error);
			var ast = callbackEngine.compile(resource(item.resource), new ScriptContext("InvalidStaticInitializer"));
			if (ast != null || callbackError == null || callbackError.indexOf(item.message) == -1)
				throw 'initializer rejection callback failed for ${item.name}: $callbackError';

			var thrown:Dynamic = null;
			try {
				new Haxiom().compile(resource(item.resource), new ScriptContext("InvalidStaticInitializer"));
			} catch (error:Dynamic) {
				thrown = error;
			}
			if (thrown == null || Std.string(thrown).indexOf(item.message) == -1)
				throw 'initializer rejection throw failed for ${item.name}: ${Std.string(thrown)}';
		}
	}

	static function testSemantics(path:StaticInitializerPath):Void {
		var actual = Std.string(execute(path, resource("haxiom.scenario.initializer.valid"), "StaticInitializerScenario", _ -> {}));
		if (actual != "41|42|first,second|2")
			throw 'static initializer semantics via ${pathLabel(path)} returned $actual';
	}

	static function testImportSandbox(path:StaticInitializerPath):Void {
		expectFailure(() -> execute(path, resource("haxiom.scenario.initializer.sandbox.import"), "StaticInitializerImportSandbox", _ -> {}),
			'Identifier "Sys" not found', 'system API sandbox via ${pathLabel(path)}');
	}

	static function testFieldFilter(path:StaticInitializerPath):Void {
		expectFailure(() -> execute(path, resource("haxiom.scenario.initializer.sandbox.field"), "StaticInitializerFieldSandbox", engine -> {
			engine.setGlobal("hostSecret", {value: "classified"});
			engine.setFieldAccessFilter((_, field) -> field != "value");
		}), "forbidden", 'field filter via ${pathLabel(path)}');
	}

	static function testInstructionLimit(path:StaticInitializerPath):Void {
		expectFailure(() -> execute(path, resource("haxiom.scenario.initializer.limit.instructions"), "StaticInitializerInstructionLimit", engine -> {
			engine.maxInstructions = 1000;
		}), "Instruction limit exceeded", 'instruction limit via ${pathLabel(path)}');
	}

	static function execute(path:StaticInitializerPath, source:String, moduleName:String, configure:Haxiom->Void):Dynamic {
		var context = new ScriptContext(moduleName, 'test/scenarios/$moduleName.hx');
		var engine = new Haxiom();
		configure(engine);
		return switch (path) {
			case ASTInterpret | VMInterpret:
				engine.useVM = path == VMInterpret;
				engine.interpret(source, context);
			case ASTBytes:
				var bytes = new Haxiom().compileToASTBytes(source, context);
				engine.executeASTBytes(bytes, source);
			case RawHXBC | CompressedHXBC | KeyedCompressedHXBC:
				var key = path == KeyedCompressedHXBC ? BYTECODE_KEY : null;
				var bytes = new Haxiom().compileToBytecodeBytes(source, context, key, true, path != RawHXBC);
				engine.executeBytecodeBytes(bytes, source, key);
		};
	}

	static function expectFailure(action:Void->Dynamic, messagePart:String, label:String):Void {
		var caught:Dynamic = null;
		try {
			action();
		} catch (error:Dynamic) {
			caught = error;
		}
		if (caught == null || Std.string(caught).indexOf(messagePart) == -1)
			throw '$label did not fail with "$messagePart": ${Std.string(caught)}';
	}

	static function resource(name:String):String {
		var value = haxe.Resource.getString(name);
		if (value == null)
			throw 'Missing bundled static initializer resource: $name';
		return value;
	}

	static function pathLabel(path:StaticInitializerPath):String {
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
