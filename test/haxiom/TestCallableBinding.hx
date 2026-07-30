package haxiom;

class TestCallableBinding {
	static final EXPECTED = "10,11,13,16,20,25,31|0,1,3,6,10,15,21|115";

	public static function runTests():Void {
		assertResult("AST interpret", engine -> {
			engine.useVM = false;
			return engine.interpret(source(), new ScriptContext("CallableBindingMain"));
		});
		assertResult("VM interpret", engine -> {
			engine.useVM = true;
			return engine.interpret(source(), new ScriptContext("CallableBindingMain"));
		});
		assertResult("AST bytes", engine -> {
			var bytes = engine.compileToASTBytes(source(), new ScriptContext("CallableBindingMain", "CallableBindingMain.hx"));
			return engine.executeASTBytes(bytes, source());
		});
		assertResult("HXBC bytes", engine -> {
			var bytes = engine.compileToBytecodeBytes(source(), new ScriptContext("CallableBindingMain", "CallableBindingMain.hx"), null, false, false);
			return engine.executeBytecodeBytes(bytes, source());
		});
		assertResult("compressed HXBC bytes", engine -> {
			var bytes = engine.compileToBytecodeBytes(source(), new ScriptContext("CallableBindingMain", "CallableBindingMain.hx"), null, false, true);
			return engine.executeBytecodeBytes(bytes, source());
		});

		trace("SUCCESS: Callable binding paths verified.");
	}

	static function assertResult(path:String, run:Haxiom->Dynamic):Void {
		var engine = new Haxiom();
		engine.registerClass("CallableBindingHost", CallableBindingHost);
		engine.registerClass("CallableBindingHostFactory", CallableBindingHostFactory);
		var traceLines:Array<String> = [];
		var previousTrace = haxe.Log.trace;
		haxe.Log.trace = (value:Dynamic, ?infos:haxe.PosInfos) -> traceLines.push(Std.string(value));
		var actual:String = null;
		try {
			actual = Std.string(run(engine));
		} catch (e:Dynamic) {
			haxe.Log.trace = previousTrace;
			throw e;
		}
		haxe.Log.trace = previousTrace;
		if (actual != EXPECTED)
			throw 'Callable binding failed via $path: expected $EXPECTED, got $actual';
		var expectedTrace = ["one", "two, 2", "many, 1, 2, 3, 4, 5"];
		if (traceLines.join("|") != expectedTrace.join("|"))
			throw 'Variadic trace failed via $path: expected ${expectedTrace.join("|")}, got ${traceLines.join("|")}';
	}

	static function source():String {
		return '
			extern class CallableBindingHost {
				public function add(a:Int, b:Int):Int;
			}

			extern class CallableBindingHostFactory {
				static public function create(base:Int):CallableBindingHost;
			}

			class CallableTarget {
				var base:Int;

				public function new(base:Int) {
					this.base = base;
				}

				public function m0():Int return base;
				public function m1(a:Int):Int return base + a;
				public function m2(a:Int, b:Int):Int return base + a + b;
				public function m3(a:Int, b:Int, c:Int):Int return base + a + b + c;
				public function m4(a:Int, b:Int, c:Int, d:Int):Int return base + a + b + c + d;
				public function m5(a:Int, b:Int, c:Int, d:Int, e:Int):Int return base + a + b + c + d + e;

				public function many(...values:Int):Int {
					var total = base;
					for (value in values) total += value;
					return total;
				}

				public function run():String {
					var f0 = m0;
					var f1 = m1;
					var f2 = m2;
					var f3 = m3;
					var f4 = m4;
					var f5 = m5;
					var fm = many;
					var guest = [
						f0(), f1(1), f2(1, 2), f3(1, 2, 3),
						f4(1, 2, 3, 4), f5(1, 2, 3, 4, 5), fm(1, 2, 3, 4, 5, 6)
					].join(",");

					var a0 = function():Int { return 0; };
					var a1 = function(a:Int):Int { return a; };
					var a2 = function(a:Int, b:Int):Int { return a + b; };
					var a3 = function(a:Int, b:Int, c:Int):Int { return a + b + c; };
					var a4 = function(a:Int, b:Int, c:Int, d:Int):Int { return a + b + c + d; };
					var a5 = function(a:Int, b:Int, c:Int, d:Int, e:Int):Int { return a + b + c + d + e; };
					var am = function(...values:Int):Int {
						var total = 0;
						for (value in values) total += value;
						return total;
					};
					var anonymous = [
						a0(), a1(1), a2(1, 2), a3(1, 2, 3),
						a4(1, 2, 3, 4), a5(1, 2, 3, 4, 5), am(1, 2, 3, 4, 5, 6)
					].join(",");

					var hostMethod = CallableBindingHostFactory.create(100).add;
					return guest + "|" + anonymous + "|" + hostMethod(7, 8);
				}
			}

			class CallableBindingMain {
				static public function main():String {
					trace("one");
					trace("two", 2);
					trace("many", 1, 2, 3, 4, 5);
					return new CallableTarget(10).run();
				}
			}
		';
	}
}

class CallableBindingHost {
	var base:Int;

	public function new(base:Int) {
		this.base = base;
	}

	public function add(a:Int, b:Int):Int {
		return base + a + b;
	}
}

class CallableBindingHostFactory {
	public static function create(base:Int):CallableBindingHost {
		return new CallableBindingHost(base);
	}
}
