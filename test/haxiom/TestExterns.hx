package haxiom;

class HostHelper {
	public static var counter:Int = 42;
	public static function multiply(a:Int, b:Int):Int {
		return a * b;
	}
}

class ExternConstructible {
	var base:Int;

	public function new(base:Int) {
		this.base = base;
	}

	public function add(value:Int):Int {
		return base + value;
	}
}

class TestExterns {
	public static function runTests() {
		trace("Running TestExterns Suite...");
		
		testExternClassAST();
		testExternClassVM();
		testExternConstructor();
		testClassLevelExternMember();
		testMissingReturnTypeError();
		testRootLevelExternProhibitedError();
		testUnboundHostExternError();
		testStaticTypeCheckingWithExterns();
		testExternClassCannotUseExtends();
		testCannotSubclassExternClass();

		trace("TestExterns Suite Passed Successfully!");
	}

	static function testExternConstructor() {
		var source = "
			extern class ExternConstructible {
				function new(base:Int);
				function add(value:Int):Int;
			}

			class Main {
				static public function main():Int {
					return new ExternConstructible(40).add(2);
				}
			}
		";

		for (useVM in [false, true]) {
			var engine = externConstructorEngine();
			engine.useVM = useVM;
			engine.currentFilename = "Main.hx";
			assertExternConstructor(useVM ? "VM interpret" : "AST interpret", engine.interpret(source));
		}

		var astEngine = externConstructorEngine();
		var astBytes = astEngine.compileToASTBytes(source, "Main.hx");
		assertExternConstructor("AST bytes", astEngine.executeASTBytes(astBytes, source));

		for (compress in [false, true]) {
			var bytecodeEngine = externConstructorEngine();
			var bytecode = bytecodeEngine.compileToBytecodeBytes(source, "Main.hx", null, false, compress);
			assertExternConstructor(compress ? "compressed HXBC" : "HXBC", bytecodeEngine.executeBytecodeBytes(bytecode, source));
		}

		var staticEngine = externConstructorEngine();
		staticEngine.currentFilename = "Main.hx";
		assertExternConstructor("static checking", staticEngine.interpret(source, null, true));

		var invalidSource = StringTools.replace(source, "new ExternConstructible(40)", 'new ExternConstructible("invalid")');
		var invalidRejected = false;
		var invalidError:Null<String> = null;
		try {
			externConstructorEngine().interpret(invalidSource, null, true);
		} catch (e:Dynamic) {
			invalidError = Std.string(e);
			invalidRejected = invalidError.indexOf("new ExternConstructible argument 1") != -1;
		}
		if (!invalidRejected)
			throw "Static checking accepted an invalid extern constructor argument"
				+ (invalidError != null ? ": " + invalidError : " without reporting an error");
	}

	static function externConstructorEngine():Haxiom {
		var engine = new Haxiom();
		engine.registerClass("ExternConstructible", ExternConstructible);
		return engine;
	}

	static function assertExternConstructor(path:String, actual:Dynamic):Void {
		if (actual != 42)
			throw 'Extern constructor failed via $path: expected 42, got $actual';
	}

	static function testExternClassAST() {
		var engine = new Haxiom();
		engine.useVM = false;
		engine.currentFilename = "Main.hx";
		engine.registerClass("HostHelper", HostHelper);

		var script = "
			extern class HostHelper {
				static var counter:Int;
				static function multiply(a:Int, b:Int):Int;
			}

			class Main {
				static public function main():Int {
					return HostHelper.multiply(HostHelper.counter, 2);
				}
			}
		";

		var res = engine.interpret(script);
		if (res != 84) {
			throw 'testExternClassAST failed: expected 84, got $res';
		}
	}

	static function testExternClassVM() {
		var engine = new Haxiom();
		engine.useVM = true;
		engine.currentFilename = "Main.hx";
		engine.registerClass("HostHelper", HostHelper);

		var script = "
			extern class HostHelper {
				static var counter:Int;
				static function multiply(a:Int, b:Int):Int;
			}

			class Main {
				static public function main():Int {
					return HostHelper.multiply(HostHelper.counter, 3);
				}
			}
		";

		var res = engine.interpret(script);
		if (res != 126) {
			throw 'testExternClassVM failed: expected 126, got $res';
		}
	}

	static function testClassLevelExternMember() {
		var engine = new Haxiom();
		engine.useVM = true;
		engine.currentFilename = "Main.hx";
		engine.setGlobal("myHostFunc", function(val:Int):Int return val + 10);

		var script = "
			class Main {
				extern static public function myHostFunc(val:Int):Int;
				static public function main():Int {
					return myHostFunc(50);
				}
			}
		";

		var res = engine.interpret(script);
		if (res != 60) {
			throw 'testClassLevelExternMember failed: expected 60, got $res';
		}
	}

	static function testMissingReturnTypeError() {
		var engine = new Haxiom();
		var script = "
			extern class BadHost {
				static function missingRet(a:Int);
			}
		";
		var caught = false;
		try {
			engine.interpret(script);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Extern methods must explicitly define a return type") != -1) {
				caught = true;
			}
		}
		if (!caught) {
			throw "testMissingReturnTypeError failed: expected CompileException for missing return type";
		}
	}

	static function testRootLevelExternProhibitedError() {
		var engine = new Haxiom();
		var script = "
			extern function floatingFunc():Void;
			class Main {
				static public function main() {}
			}
		";
		var caught = false;
		try {
			engine.interpret(script);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Extern variables and functions must be declared inside a class or must be extern classes") != -1) {
				caught = true;
			}
		}
		if (!caught) {
			throw "testRootLevelExternProhibitedError failed: expected CompileException for root-level extern function";
		}
	}

	static function testUnboundHostExternError() {
		var engine = new Haxiom();
		engine.useVM = false;
		engine.currentFilename = "Main.hx";

		var script = "
			extern class MissingHost {
				static function doSomething():Void;
			}

			class Main {
				static public function main() {
					MissingHost.doSomething();
				}
			}
		";

		var caught = false;
		try {
			engine.interpret(script);
		} catch (e:ScriptException) {
			if (e.message.indexOf("Unbound Host Extern") != -1) {
				caught = true;
			}
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Unbound Host Extern") != -1) {
				caught = true;
			}
		}
		if (!caught) {
			throw "testUnboundHostExternError failed: expected ScriptException for unbound host extern";
		}
	}

	static function testStaticTypeCheckingWithExterns() {
		var engine = new Haxiom();
		engine.currentFilename = "Main.hx";
		engine.registerClass("HostHelper", HostHelper);

		var script = "
			extern class HostHelper {
				static function multiply(a:Int, b:Int):Int;
			}

			class Main {
				static public function main():Int {
					return HostHelper.multiply(10, 20);
				}
			}
		";

		var res:Dynamic = engine.interpret(script, null, true);
		if (res != 200) {
			throw 'testStaticTypeCheckingWithExterns failed: expected 200, got $res';
		}
	}

	static function testExternClassCannotUseExtends() {
		var engine = new Haxiom();
		var script = "
			extern class BaseHost {}
			extern class DerivedHost extends BaseHost {}
		";
		var caught = false;
		try {
			engine.interpret(script);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Extern classes in Haxiom cannot use 'extends'") != -1) {
				caught = true;
			}
		}
		if (!caught) {
			throw "testExternClassCannotUseExtends failed: expected CompileException when extern class uses extends";
		}
	}

	static function testCannotSubclassExternClass() {
		var engine = new Haxiom();
		var script = "
			extern class BaseHost {}
			class GuestSub extends BaseHost {}
		";
		var caught = false;
		try {
			engine.interpret(script);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Cannot extend extern class 'BaseHost'") != -1) {
				caught = true;
			}
		}
		if (!caught) {
			throw "testCannotSubclassExternClass failed: expected CompileException when extending an extern class";
		}
	}
}
