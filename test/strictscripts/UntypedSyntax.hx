package strictscripts;

import haxiom.Haxiom;
import haxiom.ScriptContext;
import haxiom.ScriptException;

class UntypedSyntax {
	static public function run():Void {
		var invalid = [
			"static public function main() { untyped mark(); }",
			"static var value = untyped mark();",
			"var value = untyped mark();",
			"static function unused() { return untyped 1; }",
			"static public function main() { if (false) { untyped mark(); } }",
			"static public function main() { return '${untyped mark()}'; }",
			"static public function main() { return '$untyped'; }"
		];
		for (vm in [false, true]) {
			for (body in invalid) {
				for (path in 0...6) {
					var engine = new Haxiom();
					engine.useVM = vm;
					var calls = 0;
					engine.setGlobal("mark", () -> calls++);
					var source = "class Sample {\n" + body + "\n}";
					var failed = false;
					try {
						compile(engine, source, path);
					} catch (error:ScriptException) {
						check(error);
						failed = true;
					}
					if (!failed) throw "Unsupported untyped expression compiled";
					var errors = 0;
					engine.onCompilerError = error -> { check(error); errors++; };
					if (compile(engine, source, path) != null || errors != 1 || calls != 0)
						throw "Untyped rejection failed to report once before execution";
					var valid = "// untyped\nclass Sample { /* untyped */ static public function main():String { "
						+ "var untypedValue = \"untyped\"; return untypedValue; } }";
					var result:String = engine.interpret(valid, new ScriptContext("Sample"));
					if (result != "untyped" || errors != 1) throw "Harmless text rejected or engine recovery failed";
					engine.compile("#if disabled\nuntyped mark();\n#end\nclass Inactive {}");
					if (errors != 1) throw "Inactive preprocessor branch rejected";
					engine.dispose();
				}
			}
			var importer = new Haxiom();
			importer.useVM = vm;
			importer.moduleResolver = _ -> "package dependency; class Rules { static public var value = untyped 1; }";
			var rejected = false;
			try {
				importer.interpret("import dependency.Rules; class Caller { static public function main():Int return Rules.value; }", new ScriptContext("Caller"));
			} catch (error:Dynamic) {
				rejected = Std.string(error).indexOf("'untyped' keyword is not supported") != -1;
			}
			if (!rejected) throw "Imported module accepted untyped";
			importer.dispose();
		}
	}

	static function compile(engine:Haxiom, source:String, path:Int):Dynamic {
		var context = new ScriptContext("Sample", "strict/Untyped.hx");
		return switch (path) {
			case 0: engine.compile(source, context);
			case 1: engine.interpret(source, context);
			case 2: engine.compileToBytes(source, context);
			case 3: engine.compileToASTBytes(source, context);
			case 4: engine.compileToBytecodeBytes(source, context);
			default: engine.compileToBytecodeBytes(source, context, "key", true, true);
		};
	}

	static function check(error:ScriptException):Void {
		if (error.message.indexOf("'untyped' keyword is not supported") == -1
			|| error.file != "strict/Untyped.hx" || error.line != 2 || error.col < 1)
			throw 'Incorrect untyped diagnostic: ${error.message} at ${error.file}:${error.line}:${error.col}';
	}
}
