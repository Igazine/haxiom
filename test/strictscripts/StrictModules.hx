package strictscripts;

import haxiom.Haxiom;
import haxiom.ScriptContext;
import haxiom.ScriptException;

class StrictModules {
	static public function main():Void {
		UntypedSyntax.run();
		var invalid = [
			"var value = 1;", "final value = 1;", "mark();", "new Array();", "return 1;",
			"if (true) mark();", "while (false) mark();", "for (i in 0...1) mark();",
			"{ mark(); }", "function run() { mark(); }", "@:test mark();",
			"throw 'bad';", "try { mark(); } catch (e:Dynamic) {}", "Sample.run;"
		];
		for (vm in [false, true]) {
			for (source in invalid) {
				for (path in 0...6) {
					var engine = new Haxiom();
					engine.useVM = vm;
					var calls = 0;
					engine.setGlobal("mark", () -> calls++);
					var text = "class Sample { static var initialized = mark(); static public function run():Void {} }\n" + source;
					expectCompileFailure(() -> compilePath(engine, text, path));
					var errors = 0;
					engine.onCompilerError = error -> {
						errors++;
						checkError(error);
					};
					if (compilePath(engine, text, path) != null || errors != 1 || calls != 0)
						throw 'Invalid module escaped rejection: path=$path vm=$vm source=$source';
					var recovered:Int = engine.interpret("class Recovery { static public function main():Int return 3; }", new ScriptContext("Recovery"));
					if (recovered != 3 || errors != 1)
						throw "Compiler rejection prevented subsequent module execution";
					engine.dispose();
				}
			}
			testValidModule(vm);
			testImportedModule(vm);
		}
		trace("SUCCESS: Strict script module tests passed.");
	}

	static function compilePath(engine:Haxiom, source:String, path:Int):Dynamic {
		var context = new ScriptContext("Sample", "strict/Invalid.hx");
		return switch (path) {
			case 0: engine.compile(source, context);
			case 1: engine.interpret(source, context);
			case 2: engine.compileToBytes(source, context);
			case 3: engine.compileToASTBytes(source, context);
			case 4: engine.compileToBytecodeBytes(source, context);
			default: engine.compileToBytecodeBytes(source, context, "key", true, true);
		};
	}

	static function checkError(error:ScriptException):Void {
		if (error.message.indexOf("Top-level executable code is not allowed") == -1
			|| error.line != 2 || error.file != "strict/Invalid.hx")
			throw 'Incorrect module diagnostic: ${error.message} at ${error.file}:${error.line}';
	}

	static function expectCompileFailure(run:Void->Dynamic):Void {
		try {
			run();
		} catch (error:ScriptException) {
			checkError(error);
			return;
		}
		throw "Invalid module compiled successfully";
	}

	static function testValidModule(vm:Bool):Void {
		var source = "package example; import haxe.io.Bytes; using StringTools; "
			+ "interface Contract { function run():Int; } typedef Count = Int; enum Choice { One; } "
			+ "abstract Number(Int) {} "
			+ "class Sample { public function new() {} static public function main():Int return 42; } "
			+ "class Other { static public function main():Int { throw 'wrong main'; } }";
		var context = new ScriptContext("Sample");
		for (path in 0...4) {
			var engine = new Haxiom();
			engine.useVM = vm;
			var result:Int = switch (path) {
				case 0: engine.interpret(source, context);
				case 1: engine.executeASTBytes(engine.compileToASTBytes(source, context));
				case 2: engine.executeBytecodeBytes(engine.compileToBytecodeBytes(source, context));
				default: engine.executeBytecodeBytes(engine.compileToBytecodeBytes(source, context, "key", true, true), null, "key");
			};
			if (result != 42) throw 'Valid module failed via path $path';
			engine.dispose();
		}
		var definitions = new Haxiom();
		definitions.useVM = vm;
		definitions.interpret("class Dormant { static public function main():Void { throw 'unexpected main'; } }");
		definitions.interpret("class Another { static public function main():Void { throw 'unexpected main'; } }", new ScriptContext("Different"));
		definitions.compile("// empty module\n");
		definitions.compile("#if disabled\nmark();\n#end\nclass Active {}", new ScriptContext("Active"));
		definitions.dispose();
	}

	static function testImportedModule(vm:Bool):Void {
		var engine = new Haxiom();
		engine.useVM = vm;
		var calls = 0;
		engine.setGlobal("mark", () -> calls++);
		engine.moduleResolver = _ -> "package dependency; class Rules { static public function run():Int return 7; }\nmark();";
		var failed = false;
		try {
			engine.interpret("import dependency.Rules; class Caller { static public function main():Int return Rules.run(); }", new ScriptContext("Caller"));
		} catch (error:Dynamic) {
			failed = Std.string(error).indexOf("Top-level executable code is not allowed") != -1;
		}
		if (!failed || calls != 0) throw "Imported module executed top-level code";
		engine.dispose();
	}
}
