package haxiom;

import haxiom.Interp.Scope;

class TestHaxiom {
	static function main() {
		trace("Haxiom Foundation Verification Suite");
		trace("------------------------------------");

		var haxiom = new haxiom.Haxiom();
		runPart1(haxiom);
		runPart2(haxiom);
		runPart3(haxiom);
		runPart4(haxiom);

		// Run Async/Await VM Verification Suite
		TestAsyncVM.runTests(() -> {
			TestCompilationFeatures.runTests();
			TestHXBCSecurityDebug.runTests();
			TestStaticTypeChecker.runTests();
			TestDCE.runTests();
			TestInlineCache.main();
			TestSafeguardsTCO.runTests();
			trace("ALL TESTS COMPLETED SUCCESSFULLY!");
		});
	}

	static function runPart1(haxiom:haxiom.Haxiom) {
		// 1. Basic variables, discarded types, ternary, arithmetic, and unops
		var script1 = '
            var a:Int = 10;
            var b:Float = 20.5;
            var c = a + b;
            var cond:Bool = c > 30;
            var result = cond ? "yes" : "no";
            var x = 5;
            var postfix = x++;
            var prefix = ++x;
            trace("Basic Math & Types: " + result);
            trace("Postfix x++: " + postfix);
            trace("Prefix ++x: " + prefix);
        ';
		haxiom.interpret(script1);

		// 2. Control flow: do-while, while, switch-case
		var script2 = '
            var i = 0;
            var whileRes = 0;
            while (i < 3) {
                i++;
                whileRes += i;
            }
            
            var j = 0;
            var doRes = 0;
            do {
                j++;
                doRes += j;
            } while (j < 3);

            var switchVal = "banana";
            var fruit = "unknown";
            switch (switchVal) {
                case "apple": fruit = "red";
                case "banana", "lemon": fruit = "yellow";
                default: fruit = "none";
            }
            
            trace("While Loop Res: " + whileRes);
            trace("Do-While Loop Res: " + doRes);
            trace("Switch Case Res: " + fruit);
        ';
		haxiom.interpret(script2);

		// 3. Dynamic Arrays, Anonymous structures, and subscript mapping
		var script3 = '
            var arr:Array<Int> = [1, 2, 3];
            arr[1] = 42;
            var obj:Dynamic = { x: 10, y: "tamas" };
            obj.x = 99;
            trace("Array Subscript: " + arr[1]);
            trace("Anonymous Struct: " + obj.x + ", " + obj.y);
        ';
		haxiom.interpret(script3);

		// 4. Haxe Iterator protocol compatibility on Haxiom loops
		var script4 = '
            var items = ["apple", "cherry"];
            var loopOutput = "";
            for (item in items) {
                loopOutput = loopOutput + item + " ";
            }
            trace("Iterable loop: " + loopOutput);
        ';
		haxiom.interpret(script4);

		// 5. Dynamic Object-Oriented Programming (extends, fields, methods, constructors, super)
		var script5 = '
            class Animal {
                public var name:String;
                public function new(name:String) {
                    this.name = name;
                }
                public function speak():String {
                    return name + " speaks";
                }
            }

            class Dog extends Animal {
                public function new(name:String) {
                    super(name);
                }
                public function speak():String {
                    return name + " barks: " + super.speak();
                }
            }

            var d:Animal = new Dog("Fido");
            trace("OOP Chaining: " + d.speak());
        ';
		haxiom.interpret(script5);

		// 6. Closures, arrow function lambdas
		var script6 = '
            var multiply = (x:Int, y:Int):Int -> x * y;
            var adder = function(x, y) { return x + y; };
            trace("Arrow Function: " + multiply(6, 7));
            trace("Formal Closure: " + adder(5, 5));
        ';
		haxiom.interpret(script6);

		// 7. Map Literals, additions and subscript mapping
		var script7 = '
            var m = ["apple" => 10, "banana" => 20];
            m["cherry"] = 30;
            trace("Map Literal string-key value: " + m["apple"]);
            trace("Map Literal cherry-key value: " + m["cherry"]);
            
            var intMap = [100 => "one-hundred", 200 => "two-hundred"];
            trace("Map Literal int-key value: " + intMap[200]);
        ';
		haxiom.interpret(script7);

		// 8. Properties with custom getters and setters
		var script8 = '
            class Player {
                public var x(get, set):Float;
                private var _x:Float = 0.0;
                
                public function new() {}
                
                public function get_x():Float {
                    return _x + 10.0;
                }
                
                public function set_x(v:Float):Float {
                    return _x = v * 2.0;
                }
            }
            
            var p = new Player();
            p.x = 5.0; // setter: _x = 5.0 * 2.0 = 10.0
            trace("Property getter/setter check: " + p.x); // getter: _x + 10.0 = 20.0
        ';
		haxiom.interpret(script8);

		// 9. Std Standard Library & isOfType Type Queries
		var script9 = '
            class Base {}
            class Derived extends Base {}
            
            var d = new Derived();
            var isDerived = Std.isOfType(d, Derived);
            var isBase = Std.isOfType(d, Base);
            
            var parsed = Std.parseInt("123");
            var strVal = Std.string(parsed + 1);
            
            trace("Std.isOfType Derived check: " + isDerived);
            trace("Std.isOfType Base check: " + isBase);
            trace("Std.parseInt & Std.string check: " + strVal);
        ';
		haxiom.interpret(script9);

		// 10. Strict Type Enforcement (Successful typed assignments)
		var script10 = '
            var name:String = "tamas";
            var age:Int = 35;
            var height:Float = 1.75;
            var active:Bool = true;
            
            // Valid re-assignments
            name = "sopronyi";
            age = 36;
            height = 1.8; 
            
            trace("Valid typed vars: " + name + ", age: " + age + ", height: " + height);
        ';
		haxiom.interpret(script10);

		// 11. Type Violation Exception Catching
		try {
			var script11 = '
                var count:Int = 10;
                count = "hello"; // Type mismatch! Should throw runtime error
            ';
			haxiom.interpret(script11);
			trace("FAILURE: count = 'hello' should have thrown an error");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected count type mismatch: " + e);
		}

		try {
			var script12 = '
                class User {
                    public var email:String;
                    public function new() {}
                }
                var u = new User();
                u.email = 123; // Type mismatch on class field! Should throw
            ';
			haxiom.interpret(script12);
			trace("FAILURE: u.email = 123 should have thrown an error");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected class field type mismatch: " + e);
		}

		try {
			var script13 = '
                var square = function(v:Int):Int {
                    return "not-an-int"; // Type mismatch on return value! Should throw
                };
                square(5);
            ';
			haxiom.interpret(script13);
			trace("FAILURE: return 'not-an-int' should have thrown an error");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected method return type mismatch: " + e);
		}

		// 12. Package Namespaces
		var script14 = '
            package game.core;
            class Player {
                public var name:String;
                public function new(name:String) {
                    this.name = name;
                }
            }
        ';
		haxiom.interpret(script14);
		var script14_eval = '
            var p = new game.core.Player("tamas");
            trace("Package FQ inst: " + p.name);
        ';
		haxiom.interpret(script14_eval);

		// 13. Native Imports & Aliases
		var script15 = '
            import haxe.ds.StringMap;
            import haxe.ds.StringMap as MyMap;
            var m = new StringMap();
            m.set("hello", "world");
            var m2 = new MyMap();
            m2.set("hi", "there");
            trace("StringMap: " + m.get("hello") + ", MyMap: " + m2.get("hi"));
        ';
		haxiom.interpret(script15);

		// 14. Module Resolver & Script Module Imports
		haxiom.moduleResolver = (fqName:String) -> {
			if (fqName == "entities.Enemy") {
				return '
                    package entities;
                    class Enemy {
                        public var hp:Int;
                        public function new(hp:Int) {
                            this.hp = hp;
                        }
                    }
                ';
			}
			return null;
		};
		var script16 = '
            import entities.Enemy;
            import entities.Enemy as ShortEnemy;
            var e = new Enemy(100);
            var e2 = new ShortEnemy(200);
            trace("Imported Enemy HP: " + e.hp + ", ShortEnemy HP: " + e2.hp);
        ';
		haxiom.interpret(script16);

		// 15. Native Exception Handling (try, catch, throw)
		var script17 = '
            var res = "";
            try {
                throw "thrown-error";
            } catch (e:String) {
                res = "Caught string: " + e;
            } catch (e:Dynamic) {
                res = "Caught dynamic: " + e;
            }
            trace("Try-Catch String: " + res);
            
            var res2 = "";
            try {
                throw 123;
            } catch (e:String) {
                res2 = "Caught string: " + e;
            } catch (e:Dynamic) {
                res2 = "Caught dynamic: " + e;
            }
            trace("Try-Catch Dynamic/Int: " + res2);
        ';
		haxiom.interpret(script17);

		// 16. Casting (unsafe and safe checked)
		var script18 = '
            var x:Dynamic = "hello";
            var s = cast(x, String);
            trace("Checked Cast String: " + s);
            var uns = cast x;
            trace("Unsafe Cast: " + uns);
        ';
		haxiom.interpret(script18);

		try {
			var script18_err = '
                var x:Dynamic = 123;
                var s = cast(x, String);
            ';
			haxiom.interpret(script18_err);
			trace("FAILURE: cast(123, String) should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected cast mismatch error: " + e);
		}

		// 17. Final Immutability (locals)
		try {
			var script19_var = '
                final x = 10;
                x = 20;
            ';
			haxiom.interpret(script19_var);
			trace("FAILURE: final x reassignment should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected final local variable reassignment error: " + e);
		}

		// 18. Final Immutability (class fields)
		var script19_cls = '
            class Vector2D {
                public final x:Float;
                public function new(x:Float) {
                    this.x = x;
                }
            }
            var v = new Vector2D(5.0);
            trace("Final field initialized: " + v.x);
        ';
		haxiom.interpret(script19_cls);

		try {
			var script19_cls_err = '
                class Vector2D {
                    public final x:Float;
                    public function new(x:Float) {
                        this.x = x;
                    }
                }
                var v = new Vector2D(5.0);
                v.x = 10.0;
            ';
			haxiom.interpret(script19_cls_err);
			trace("FAILURE: final field reassignment should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected final field reassignment error: " + e);
		}

		// 19. Final Immutability (static fields)
		try {
			var script19_static_err = '
                class Config {
                    public static final VERSION = "1.0.0";
                }
                Config.VERSION = "2.0.0";
            ';
			haxiom.interpret(script19_static_err);
			trace("FAILURE: static final field reassignment should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected static final field reassignment error: " + e);
		}
	}

	static function runPart2(haxiom:haxiom.Haxiom) {
		// 20. Unified Base Interfaces

		// 21. Interfaces & Implements Contract Conformance
		var script21_ok = '
            interface IUpdatable {
                function update(dt:Float):Void;
            }
            class Game implements IUpdatable {
                public function new() {}
                public function update(dt:Float):Void {
                    trace("Game updated: " + dt);
                }
            }
            var g = new Game();
            g.update(0.16);
        ';
		haxiom.interpret(script21_ok);

		// Conformance Mismatch Validation Checks
		try {
			var script21_err = '
                interface IUpdatable {
                    function update(dt:Float):Void;
                }
                class Game implements IUpdatable {
                    public function new() {}
                    public function update():Void {} // Argument count mismatch!
                }
            ';
			haxiom.interpret(script21_err);
			trace("FAILURE: interface signature mismatch should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected interface signature mismatch: " + e);
		}

		// 22. Std.isOfType Interface Validation
		var script22 = '
            interface IRenderable {
                function render():Void;
            }
            class Player implements IRenderable {
                public function new() {}
                public function render():Void {
                    trace("Player rendered");
                }
            }
            var p = new Player();
            trace("isOfType Player: " + Std.isOfType(p, Player));
            trace("isOfType IRenderable: " + Std.isOfType(p, IRenderable));
        ';
		haxiom.interpret(script22);

		// 23. Standard Math Library Integration
		var script23 = '
            trace("Math.abs: " + Math.abs(-15));
            trace("Math.min: " + Math.min(10, 20));
            trace("Math.max: " + Math.max(10, 20));
        ';
		haxiom.interpret(script23);

		// 24. Call Stack & Stack Trace Diagnostics
		try {
			var script24 = '
                class TestTrace {
                    public function new() {}
                    public function error():Void {
                        throw "thrown-nested-error";
                    }
                    public function run():Void {
                        this.error();
                    }
                }
                var tt = new TestTrace();
                tt.run();
            ';
			haxiom.interpret(script24);
			trace("FAILURE: nested exception should have thrown detailed stack trace");
		} catch (e:Dynamic) {
			var strErr = Std.string(e);
			trace("SUCCESS: Caught expected virtual call stack trace:\n" + strErr);
		}

		// 25. Enums & Advanced Switch Pattern Matching
		var script25 = '
            enum Status {
                Idle;
                Active(speed:Float);
                Error(code:Int, msg:String);
            }
            
            var s1 = Idle;
            var s2 = Active(5.5);
            var s3 = Error(404, "Not Found");
            
            function checkStatus(s:Status):String {
                switch (s) {
                    case Idle: return "idle";
                    case Active(spd): return "active at " + spd;
                    case Error(code, _): return "error code " + code;
                }
            }
            
            trace("check s1: " + checkStatus(s1));
            trace("check s2: " + checkStatus(s2));
            trace("check s3: " + checkStatus(s3));
        ';
		haxiom.interpret(script25);

		// 26. Encapsulation Access Enforcements (Default Private)
		var script26_class = '
            class Account {
                var balance:Float = 100.0; // Defaults to private!
                public var name:String = "savings";
                
                public function new() {}
                
                function internalAccess():Void { // Defaults to private!
                    trace("internal call balance: " + balance);
                }
                
                public function perform():Void {
                    internalAccess(); // Allowed from within class
                }
            }
            var acc = new Account();
            acc.perform();
        ';
		haxiom.interpret(script26_class);

		// Assert that external access to private balance fails
		try {
			haxiom.interpret('
                var acc = new Account();
                trace(acc.balance);
            ');
			trace("FAILURE: external access to private balance should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected private field access error: " + e);
		}

		// Assert that external access to private internalAccess fails
		try {
			haxiom.interpret('
                var acc = new Account();
                acc.internalAccess();
            ');
			trace("FAILURE: external access to private method should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected private method access error: " + e);
		}

		// Assert private constructor access violation
		try {
			haxiom.interpret('
                class PrivateCtor {
                    private function new() {}
                }
                var p = new PrivateCtor();
            ');
			trace("FAILURE: instantiating class with private constructor should have thrown");
		} catch (e:Dynamic) {
			trace("SUCCESS: Caught expected private constructor access error: " + e);
		}

		// 27. Custom ScriptException and configurable errorHandler
		var script27_err = '
            function fail():Void {
                throw "script-exception-test";
            }
            fail();
        ';

		// Assert default ScriptException wrapping
		try {
			haxiom.interpret(script27_err);
			trace("FAILURE: script error should have thrown ScriptException");
		} catch (e:haxiom.ScriptException) {
			trace("SUCCESS: Caught expected haxiom.ScriptException: " + e.message);
			trace("Raw value: " + e.rawValue);
		}

		// Assert errorHandler callback intercepting exception silently
		var intercepted:haxiom.ScriptException = null;
		haxiom.errorHandler = (err) -> {
			intercepted = err;
		};
		var result = haxiom.interpret(script27_err);
		haxiom.errorHandler = null; // Clean up

		if (result == null && intercepted != null) {
			trace("SUCCESS: Captured script error via errorHandler silently: " + intercepted.rawValue);
		} else {
			trace("FAILURE: errorHandler did not capture exception silently");
		}

		// 28. Caching Compiler (compile once, execute multiple times)
		var source28 = '
            var count = 0;
            function tick():Int {
                count = count + 1;
                return count;
            }
        ';
		var ast = haxiom.compile(source28, "physics_tick.hx");
		haxiom.execute(ast); // Initial load
		var runTick:Int = haxiom.interpret('tick();');
		trace("tick 1: " + runTick);
		var runTick2:Int = haxiom.interpret('tick();');
		trace("tick 2: " + runTick2);

		// 29. Strongly Typed Generic Return Values & Callbacks
		var callbackVal:String = null;
		var name:String = haxiom.interpret("return 'Alice';", (val:String) -> {
			callbackVal = val;
		});
		trace("strongly typed name: " + name);
		trace("strongly typed callback: " + callbackVal);

		// 30. Standard Library String & Array Extensions
		var script30 = '
            // String method assertions
            var s = "Haxiom-Script";
            trace("str.length: " + s.length);
            trace("str.charAt(0): " + s.charAt(0));
            trace("str.charCodeAt(0): " + s.charCodeAt(0));
            trace("str.indexOf(\'x\'): " + s.indexOf("x"));
            trace("str.lastIndexOf(\'i\'): " + s.lastIndexOf("i"));
            trace("str.substring(0, 7): " + s.substring(0, 7));
            trace("str.toLowerCase(): " + s.toLowerCase());
            trace("str.toUpperCase(): " + s.toUpperCase());
            
            var parts = s.split("-");
            trace("str.split length: " + parts.length);
            trace("str.split[0]: " + parts[0]);
            trace("str.split[1]: " + parts[1]);
            
            // Array method assertions
            var a = [10, 20, 30];
            trace("arr.length before: " + a.length);
            
            var newLen = a.push(40);
            trace("arr.length after push: " + a.length + ", push returned: " + newLen);
            trace("arr[3]: " + a[3]);
            
            var popped = a.pop();
            trace("arr.pop: " + popped + ", arr.length: " + a.length);
            
            var shifted = a.shift();
            trace("arr.shift: " + shifted + ", arr.length: " + a.length);
            
            a.unshift(5);
            trace("arr.unshift: " + a[0] + ", arr.length: " + a.length);
            
            var removed = a.remove(20);
            trace("arr.remove(20): " + removed + ", arr.length: " + a.length);
            
            var idx = a.indexOf(30);
            trace("arr.indexOf(30): " + idx);
            
            var sliceRes = a.slice(0, 1);
            trace("arr.slice(0, 1) length: " + sliceRes.length + ", item: " + sliceRes[0]);
            
            var joined = a.join("|");
            trace("arr.join: " + joined);
            
            // Closure binding extraction
            var extractPush = a.push;
            extractPush(99);
            trace("extracted push item: " + a[a.length - 1]);
        ';
		haxiom.interpret(script30);

		// 31. Precision Error Reporting (Line/Column diagnostics)

		// A. Syntax / Parser Error Position Verification
		try {
			haxiom.interpret("var x = ;");
			trace("FAILURE: syntax error 'var x = ;' should have thrown");
		} catch (e:Dynamic) {
			var msg = Std.string(e);
			if (msg.indexOf("1:9") != -1) {
				trace("SUCCESS: Caught syntax error with precise position: " + msg);
			} else {
				trace("FAILURE: syntax error did not contain expected position 1:9, got: " + msg);
			}
		}

		// B. Runtime Error Position Verification (toplevel)
		try {
			haxiom.interpret("
                var a:Int = 10;
                a = 'not-an-int';
            ");
			trace("FAILURE: type mismatch should have thrown");
		} catch (e:haxiom.ScriptException) {
			if (e.message.indexOf("script:3:21") != -1) {
				trace("SUCCESS: Caught runtime type mismatch with precise coordinates: " + e.message);
			} else {
				trace("FAILURE: runtime type mismatch stack trace did not contain script:3:21, got: " + e.message);
			}
		}

		// C. Runtime Error Position Verification (nested frame)
		try {
			haxiom.interpret("
                class Tester {
                    public function new() {}
                    public function fail():Void {
                        var list = null;
                        list[0] = 100;
                    }
                }
                var t = new Tester();
                t.fail();
            ");
			trace("FAILURE: null access should have thrown");
		} catch (e:haxiom.ScriptException) {
			if (e.message.indexOf("script:6:30") != -1) {
				trace("SUCCESS: Caught nested runtime exception with precise coordinates: " + e.message);
			} else {
				trace("FAILURE: nested runtime exception stack trace did not contain script:6:30, got: " + e.message);
			}
		}

		// 32. Single-Quoted String Interpolation
		var script32 = '
            var name = "world";
            var x = 10;
            
            // Simple variable interpolation
            var s1 = \'Hello $$name!\';
            trace("s1: " + s1);
            
            // Complex expression interpolation
            var s2 = \'val: $${x + 5}\';
            trace("s2: " + s2);
            
            // Multiple interpolations
            var s3 = \'$$name: $${x * 2} -> $$x\';
            trace("s3: " + s3);
            
            // Escapes
            var s4 = \'escaped $$$$ and \\$$x\';
            trace("s4: " + s4);
        ';
		haxiom.interpret(script32);

		// 33. Expanded Math & Primitives Standard Library
		var script33 = '
            // Math constants and rounding
            trace("Math.PI: " + Math.PI);
            trace("Math.abs(-12.5): " + Math.abs(-12.5));
            trace("Math.floor(4.9): " + Math.floor(4.9));
            trace("Math.ceil(4.1): " + Math.ceil(4.1));
            trace("Math.round(4.5): " + Math.round(4.5));
            
            // Math trigonometry & algebra
            trace("Math.sqrt(16): " + Math.sqrt(16));
            trace("Math.pow(2, 8): " + Math.pow(2, 8));
            trace("Math.sin(0): " + Math.sin(0));
            trace("Math.cos(0): " + Math.cos(0));
            
            // Math random check
            var rand = Math.random();
            trace("Math.random valid: " + (rand >= 0.0 && rand < 1.0));
            
            // Math as closure
            var myCos = Math.cos;
            trace("Math closure cos(0): " + myCos(0));
            
            // String substr
            var s = "Haxiom-Script";
            trace("str.substr(0, 7): " + s.substr(0, 7));
            trace("str.substr(7): " + s.substr(7));
            
            // Array copy, filter, map
            var arr = [1, 2, 3, 4, 5];
            var arrCopy = arr.copy();
            trace("arr.copy length: " + arrCopy.length + ", item: " + arrCopy[2]);
            
            var evenArr = arr.filter(function(x) { return x % 2 == 0; });
            trace("arr.filter length: " + evenArr.length + ", items: " + evenArr[0] + ", " + evenArr[1]);
            
            var squaredArr = arr.map(function(x) { return x * x; });
            trace("arr.map length: " + squaredArr.length + ", items: " + squaredArr[0] + ", " + squaredArr[1]);
        ';
		haxiom.interpret(script33);

		// 34. Interface Default Implementations (Native-style Traits)
		var script34 = '
            interface IGreetable {
                function greet(name:String):String {
                    return "Default hello to " + name;
                }
                function welcome():String; // standard signature
            }
            
            class User implements IGreetable {
                public function new() {}
                public function welcome():String {
                    return "Welcome to User class";
                }
            }
            
            class SpecialUser implements IGreetable {
                public function new() {}
                public function greet(name:String):String {
                    return "Overridden hello to " + name;
                }
                public function welcome():String {
                    return "Welcome to SpecialUser class";
                }
            }
            
            var u = new User();
            var su = new SpecialUser();
            
            trace("u.greet: " + u.greet("Alice")); // Should invoke default implementation!
            trace("u.welcome: " + u.welcome());   // Should invoke concrete implementation!
            trace("su.greet: " + su.greet("Bob"));  // Should invoke overridden implementation!
        ';
		haxiom.interpret(script34);

		// 35. Haxe API Parity & Stability Polishing
		var expectError = function(script:String, expectedSnippet:String, label:String) {
			TestHaxiom.expectError(haxiom, script, expectedSnippet, label);
		};

		// Assert Math validation (direct and closure)
		expectError('Math.abs();', "Method Math.abs expected between 1 and 1 arguments but got 0", "Math.abs direct no-args");
		expectError('Math.abs("hello");', "Math.abs expected a number for argument but got String", "Math.abs direct wrong-type");
		expectError('var f = Math.abs; f("hello");', "Math.abs expected a number for argument but got String", "Math.abs closure wrong-type");
		expectError('Math.min(10);', "Method Math.min expected between 2 and 2 arguments but got 1", "Math.min direct too-few-args");
		expectError('Math.min(10, "hello");', "Math.min expected a number for b but got String", "Math.min direct second-arg wrong-type");

		// Assert String validation (direct and closure)
		expectError('"hello".split();', "Method String.split expected between 1 and 1 arguments but got 0", "String.split direct no-args");
		expectError('"hello".split(123);', "String.split expected a String for delimiter but got Int", "String.split direct wrong-type");
		expectError('var f = "hello".split; f(123);', "String.split expected a String for delimiter but got Int", "String.split closure wrong-type");
		expectError('"hello".substring("a");', "String.substring expected an Int for start index but got String",
			"String.substring direct start-index wrong-type");
		expectError('"hello".substring(1, "b");', "String.substring expected an Int for end index but got String",
			"String.substring direct end-index wrong-type");

		// Assert Array validation (direct and closure)
		expectError('[1, 2].filter(123);', "Array.filter expected a function for callback but got Int", "Array.filter direct wrong-type");
		expectError('var f = [1, 2].filter; f(123);', "Array.filter expected a function for callback but got Int", "Array.filter closure wrong-type");
		expectError('[1, 2].join(123);', "Array.join expected a String for separator but got Int", "Array.join direct wrong-type");

		// 36. Null Safety: Coalescing (??) and Safe Navigation (?.)
		var script36 = '
            var a = null;
            var b = a ?? "fallback";
            trace("Coalesce null: " + b);
            
            var c = "hello" ?? "fallback";
            trace("Coalesce value: " + c);
            
            var obj:Dynamic = null;
            var field = obj?.someField;
            trace("Safe field null: " + field);
            
            var methodRes = obj?.someMethod(1, 2);
            trace("Safe method null: " + methodRes);
            
            var realObj:Dynamic = { value: "tamas" };
            var safeReal = realObj?.value;
            trace("Safe field value: " + safeReal);
        ';
		haxiom.interpret(script36);

		// 37. Range Iteration (0...5)
		var script37 = '
            var count = 0;
            for (i in 0...5) {
                count += i;
            }
            trace("Range iteration sum (0-4): " + count);
        ';
		haxiom.interpret(script37);

		// 38. Newly Exposed Stdlib Parity Methods
		var script38 = '
            // String additions
            var s = "  haxiom  ";
            trace("StringTools.trim: " + s.trim());
            trace("StringTools.startsWith: " + s.trim().startsWith("hax"));
            trace("StringTools.endsWith: " + s.trim().endsWith("iom"));
            trace("StringTools.replace: " + s.trim().replace("iom", "io"));
            
            // Array additions
            var arr = [10, 20];
            arr.insert(1, 15);
            trace("Array.insert: " + arr.join(","));
            arr.reverse();
            trace("Array.reverse: " + arr.join(","));
            arr.sort(function(a, b) { return a - b; });
            trace("Array.sort: " + arr.join(","));
            trace("Array.contains: " + arr.contains(15));
            
            // Math additions
            trace("Math.asin(0): " + Math.asin(0));
            trace("Math.acos(1): " + Math.acos(1));
            trace("Math.isNaN: " + Math.isNaN(Math.NaN));
            
            // Map parity
            var map = ["x" => 1, "y" => 2];
            trace("Map.exists: " + map.exists("x"));
            map.remove("x");
            trace("Map.exists post remove: " + map.exists("x"));
            map.clear();
            trace("Map.exists post clear: " + map.exists("y"));
        ';
		haxiom.interpret(script38);

		// 39. Runtime FFI registration
		FFI.registerClass(haxiom, "haxiom.FFIClassHelper", FFIClassHelper);
		FFI.registerValue(haxiom, "haxiom.ffiValue", 123.45);
		var script39 = '
            var val = haxiom.ffiValue;
            var helper = new haxiom.FFIClassHelper(2);
            trace("FFI registered value: " + val);
            trace("FFI registered class call: " + helper.multiply(10));
        ';
		haxiom.interpret(script39);

		// 40. Macro Auto-Exposure FFI
		FFI.registerExposedClasses(haxiom);
		var script40 = '
            var exposed = new haxiom.ExposedNativeClass(3);
            trace("Macro auto-exposed class call: " + exposed.multiply(10));
        ';
		haxiom.interpret(script40);
	}

	static function runPart3(haxiom:haxiom.Haxiom) {
		var expectError = function(script:String, expectedSnippet:String, label:String) {
			TestHaxiom.expectError(haxiom, script, expectedSnippet, label);
		};
		// 41. Abstracts Redirection and Execution
		var color = new WrappedInt(10); // force compiler to keep abstract and its methods
		var script41 = '
            var w = new haxiom.WrappedInt(10);
            trace("Abstract value multiply: " + w.multiply(3));
            trace("Abstract getter double: " + w.double);
        ';
		try {
			haxiom.interpret(script41);
		} catch (e:Dynamic) {
			trace("Test 41 failed with exception: " + e);
			trace("Call Stack:\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}

		// 42. Generics Mapping and Instantiation
		var pairStr = new GenericPair<String>("hello"); // force Haxe compiler to generate GenericPair_String variant
		var pairInt = new GenericPair<Int>(42); // force Haxe compiler to generate GenericPair_Int variant
		var script42 = '
            var p1 = new haxiom.GenericPair<String>("tamas");
            var p2 = new haxiom.GenericPair<Int>(100);
            trace("Generic String value: " + p1.getValue());
            trace("Generic Int value: " + p2.getValue());
        ';
		haxiom.interpret(script42);

		// 43. Typed Arrays and Lists
		var forceList = new haxe.ds.List<Int>(); // force compiler to keep haxe.ds.List
		forceList.add(1);
		forceList.first();
		forceList.isEmpty();
		var script43 = '
            var arr = new Array<String>();
            arr.push("hello");
            arr.push("world");
            trace("Array<String> values: " + arr.join(", "));
            
            var list = new haxe.ds.List<Int>();
            list.add(10);
            list.add(20);
            trace("List<Int> first: " + list.first() + ", isEmpty: " + list.isEmpty());
        ';
		haxiom.interpret(script43);

		// 44. Static Extensions (using)
		StringTools.hex(10, 2);
		MyIntExtensions.doubleVal(2);
		var script44 = '
            import haxiom.MyIntExtensions;
            using haxiom.MyIntExtensions;
            using StringTools;
            
            var val = 21;
            trace("Custom native using: " + val.doubleVal());
            
            var hexVal = 255;
            trace("StringTools using: " + hexVal.hex(4));
            
            class LocalExt {
                public static function square(n:Int):Int {
                    return n * n;
                }
            }
            
            using LocalExt;
            var num = 5;
            trace("Local script using: " + num.square());
        ';
		haxiom.interpret(script44);

		// 45. Array/Generator Comprehensions
		var script45 = '
            var basic = [for (x in 0...5) x];
            trace("Basic comprehension: " + basic.join(","));
            
            var filtered = [for (x in 0...10) if (x % 2 == 0) x];
            trace("Filtered comprehension: " + filtered.join(","));
            
            var nested = [for (x in 0...3) for (y in 0...x) y];
            trace("Nested comprehension: " + nested.join(","));
            
            var blockComp = [for (x in 0...3) { var y = x * 2; y; }];
            trace("Block comprehension: " + blockComp.join(","));
            
            var x = 0;
            var whileComp = [while (x < 3) { x++; x; }];
            trace("While comprehension: " + whileComp.join(","));
            
            var switchComp = [for (c in ["a", "b", "c"]) switch (c) {
                case "a": 10;
                case "b": 20;
                default: 30;
            }];
            trace("Switch comprehension: " + switchComp.join(","));
        ';
		haxiom.interpret(script45);

		// 46. Switch-Case Pattern Guards
		var script46 = '
            var checkVal = function(x:Int):String {
                switch (x) {
                    case v if (v < 0): return "negative";
                    case v if (v == 0): return "zero";
                    case v if (v > 0 && v < 10): return "small positive";
                    default: return "large positive";
                }
            };
            trace("Guard check -5: " + checkVal(-5));
            trace("Guard check 0: " + checkVal(0));
            trace("Guard check 5: " + checkVal(5));
            trace("Guard check 20: " + checkVal(20));

            enum TestColor {
                Red(intensity:Int);
                Green;
            }
            
            var checkColor = function(c:TestColor):String {
                switch (c) {
                    case Red(i) if (i > 100): return "bright red";
                    case Red(i) if (i <= 100): return "dark red";
                    case Green: return "green";
                }
            };
            
            trace("Enum guard bright red: " + checkColor(Red(150)));
            trace("Enum guard dark red: " + checkColor(Red(50)));
            trace("Enum guard green: " + checkColor(Green));
        ';
		haxiom.interpret(script46);

		// 47. Structural/Anonymous Type Validation
		var script47 = '
            // 1. Successful matching on literal object
            var p:{name:String, age:Int} = {name: "tamas", age: 36};
            trace("Anon match name: " + p.name + ", age: " + p.age);
            
            // 2. Successful nested matching
            var p2:{name:String, address:{city:String}} = {name: "tamas", address: {city: "Budapest"}};
            trace("Anon nested match city: " + p2.address.city);
            
            // 3. Class structural compatibility
            class UserClass {
                public var name:String = "Alice";
                public var age:Int = 25;
                public function new() {}
            }
            var u:{name:String, age:Int} = new UserClass();
            trace("Anon class compatibility name: " + u.name);
        ';
		haxiom.interpret(script47);

		// Assert validation errors
		expectError('var p:{name:String, age:Int} = {name: "tamas"};', 'object is missing field "age"', "anon type missing field");
		expectError('var p:{name:String, age:Int} = {name: "tamas", age: "thirty-six"};',
			'Type mismatch in field "age": Type mismatch: expected Int but got String', "anon type wrong field type");

		// 48. Improved Error Reporting (Line/Column info in runtime errors)
		try {
			haxiom.interpret("
                var a:Int = 10;
                a = 'not-an-int';
            ");
			throw "FAIL: expected ScriptException for invalid assignment";
		} catch (e:haxiom.ScriptException) {
			if (e.line == 3 && e.col == 21 && e.file == "script") {
				trace("SUCCESS: ScriptException contains correct coordinates properties (line 3, col 21)");
			} else {
				throw "FAIL: ScriptException coordinate properties did not match. Expected line 3, col 21, file 'script' but got: "
					+ e.line
					+ ":"
					+ e.col
					+ " in "
					+ e.file;
			}
			if (e.message.split("\n")[0].indexOf("at script:3:21") != -1) {
				trace("SUCCESS: ScriptException first message line contains location details: " + e.message.split("\n")[0]);
			} else {
				throw "FAIL: ScriptException first line of message does not contain 'at script:3:21': " + e.message;
			}
		}

		// 49. Expanded Standard Library
		var script49 = '
            // 1. Std.isOfType on native types
            trace("isOfType Array: " + Std.isOfType([], Array));
            trace("isOfType Map: " + Std.isOfType(["x" => 1], Map));
            
            // 2. Global constructors & factory Map fallback
            var listInstance = new List();
            listInstance.add("item1");
            listInstance.push("item2");
            trace("List first: " + listInstance.first() + ", size: " + listInstance.toString());
            
            var mapInstance = new Map();
            mapInstance.set("key", "val");
            trace("Map fallback default key: " + mapInstance.get("key"));

            // 3. String static and instance methods
            var charA = String.fromCharCode(65);
            trace("String.fromCharCode(65): " + charA);
            
            var escaped = "hello world".urlEncode();
            trace("urlEncode: " + escaped);
            trace("urlDecode: " + escaped.urlDecode());

            // 4. StringTools usage
            trace("StringTools.hex(255): " + StringTools.hex(255));
            
            // 5. StringTools static extension (using)
            using StringTools;
            trace("replace using: " + "a-b-c".replace("-", "_"));

            // 6. Array concat method
            var a1 = [1, 2];
            var a2 = [3, 4];
            var merged = a1.concat(a2);
            trace("Array concat: " + merged.join(","));

            // 7. Lambda direct and static extension usage
            var listForLambda = [10, 20, 30];
            trace("Lambda.has 20: " + Lambda.has(listForLambda, 20));
            
            using Lambda;
            trace("Lambda exists: " + listForLambda.exists(function(x) { return x > 15; }));
        ';
		haxiom.interpret(script49);

		// 50. Interface Compliance Checking
		var script50 = '
            interface IParent {
                function parentMethod():Void;
            }
            interface IChild extends IParent {
                function childMethod():Void;
            }
            
            class GoodChild implements IChild {
                public function new() {}
                public function parentMethod():Void {}
                public function childMethod():Void {}
            }
            
            var inst = new GoodChild();
            trace("isOfType GoodChild IChild: " + Std.isOfType(inst, IChild));
            trace("isOfType GoodChild IParent: " + Std.isOfType(inst, IParent));
            
            var p:IParent = inst;
            var c:IChild = inst;
            trace("Type checking assignments passed successfully.");
        ';
		haxiom.interpret(script50);

		// Verify compile-time validation for missing parent interface method
		var script50_missing_parent = '
            interface IParent {
                function parentMethod():Void;
            }
            interface IChild extends IParent {
                function childMethod():Void;
            }
            class BadChild implements IChild {
                public function new() {}
                public function childMethod():Void {}
            }
        ';
		var errorThrown = false;
		try {
			haxiom.interpret(script50_missing_parent);
		} catch (e:Dynamic) {
			errorThrown = true;
			trace("Expected error for missing parent method caught: " + e);
		}
		if (!errorThrown) {
			throw "FAIL: Expected exception for missing parent method was not thrown.";
		}

		// Verify compile-time validation for missing child interface method
		var script50_missing_child = '
            interface IParent {
                function parentMethod():Void;
            }
            interface IChild extends IParent {
                function childMethod():Void;
            }
            class BadChild2 implements IChild {
                public function new() {}
                public function parentMethod():Void {}
            }
        ';
		errorThrown = false;
		try {
			haxiom.interpret(script50_missing_child);
		} catch (e:Dynamic) {
			errorThrown = true;
			trace("Expected error for missing child method caught: " + e);
		}
		if (!errorThrown) {
			throw "FAIL: Expected exception for missing child method was not thrown.";
		}

		// Verify compile-time validation for argument count mismatch on parent interface method
		var script50_arg_mismatch = '
            interface IParent {
                function parentMethod(arg:Int):Void;
            }
            interface IChild extends IParent {
                function childMethod():Void;
            }
            class BadChild3 implements IChild {
                public function new() {}
                public function parentMethod():Void {}
                public function childMethod():Void {}
            }
        ';
		errorThrown = false;
		try {
			haxiom.interpret(script50_arg_mismatch);
		} catch (e:Dynamic) {
			errorThrown = true;
			trace("Expected error for parent method argument count mismatch caught: " + e);
		}
		if (!errorThrown) {
			throw "FAIL: Expected exception for argument count mismatch was not thrown.";
		}

		// 51. Try-Catch Pattern Matching
		var script51 = '
            enum CatchEnum {
                ErrorA(code:Int);
                ErrorB(msg:String);
            }

            // 1. Catch standard type + guard
            var result = "";
            try {
                throw "special-error";
            } catch (e:String if (e == "special-error")) {
                result = "matched-special";
            } catch (e:String) {
                result = "matched-any-string";
            }
            trace("Catch type+guard: " + result);

            // 2. Catch enum constructor pattern matching
            var result2 = "";
            try {
                throw ErrorA(404);
            } catch (ErrorB(msg)) {
                result2 = "msg: " + msg;
            } catch (ErrorA(code)) {
                result2 = "code: " + code;
            }
            trace("Catch enum pattern: " + result2);

            // 3. Catch structural anonymous type pattern matching
            var result3 = "";
            try {
                throw { code: 500, message: "Server Error" };
            } catch ({ code: 500, message: msg }) {
                result3 = "structural-500: " + msg;
            } catch (e:Dynamic) {
                result3 = "fallback";
            }
            trace("Catch structural pattern: " + result3);
        ';
		haxiom.interpret(script51);

		// 52. Script-side Abstracts
		var script52 = '
            abstract Minutes(Float) {
                public function new(v:Float) {
                    this = v;
                }
                public function toSeconds():Float {
                    return this * 60.0;
                }
                public var doubleMinutes(get, never):Float;
                public function get_doubleMinutes():Float {
                    return this * 2.0;
                }
                public function add(v:Float):Void {
                    this = this + v;
                }
            }

            var m = new Minutes(5.0);
            trace("Abstract underlying value check: " + Std.string(m));
            trace("Abstract member call: " + m.toSeconds());
            trace("Abstract property getter call: " + m.doubleMinutes);
            m.add(10.0);
            trace("Abstract mutable this check: " + Std.string(m));
            
            // Validate type checking for abstract
            var typedM:Minutes = m;
            trace("Abstract type checking assignment passed.");
            trace("Std.isOfType abstract check: " + Std.isOfType(m, Minutes));
        ';
		haxiom.interpret(script52);

		// 53. Generic Parameter Validation
		var script53 = '
            // 1. Array validation
            var validArr:Array<Int> = [1, 2, 3];
            trace("Valid Array<Int> passed.");
        ';
		haxiom.interpret(script53);

		// Test invalid Array elements throws error
		var errorThrownArr = false;
		try {
			haxiom.interpret('var invalidArr:Array<Int> = [1, "two", 3];');
		} catch (e:Dynamic) {
			errorThrownArr = true;
			trace("Expected error for Array<Int> type mismatch caught: " + e);
		}
		if (!errorThrownArr) {
			throw "FAIL: Expected exception for invalid Array<Int> elements was not thrown.";
		}

		// Test Map type parameter validation
		var script53_map = '
            var validMap:Map<String, Int> = ["x" => 10, "y" => 20];
            trace("Valid Map<String, Int> passed.");
        ';
		haxiom.interpret(script53_map);

		var errorThrownMap = false;
		try {
			haxiom.interpret('var invalidMap:Map<String, Int> = ["x" => "ten"];');
		} catch (e:Dynamic) {
			errorThrownMap = true;
			trace("Expected error for Map<String, Int> type mismatch caught: " + e);
		}
		if (!errorThrownMap) {
			throw "FAIL: Expected exception for invalid Map<String, Int> value was not thrown.";
		}

		// 54. Script-side Generics
		var script54 = '
            class Box<T> {
                public var value:T;
                public function new(v:T) {
                    this.value = v;
                }
                public function getValue():T {
                    return this.value;
                }
            }

            // 1. Instantiate generic class
            var b1 = new Box<Int>(123);
            trace("Generic Box<Int> value: " + b1.getValue());

            var b2 = new Box<String>("hello");
            trace("Generic Box<String> value: " + b2.getValue());

            // Validate type annotation assignment
            var typedB:Box<Int> = b1;
            trace("Box<Int> assignment check passed.");

            // 2. Generic Inheritance
            class Parent<T> {
                public var value:T;
            }
            class Child<U> extends Parent<Array<U>> {}

            var c = new Child<Int>();
            c.value = [10, 20, 30];
            trace("Generic Parent.value check: " + c.value.join(","));

            // 3. Generic Interface Compliance
            interface IContainer<T> {
                function getValue():T;
            }
            class IntBox implements IContainer<Int> {
                var value:Int;
                public function new(v:Int) {
                    this.value = v;
                }
                public function getValue():Int {
                    return this.value;
                }
            }
            var ib = new IntBox(456);
            trace("IntBox implements IContainer<Int> check: " + ib.getValue());
            trace("Std.isOfType(ib, IContainer) check: " + Std.isOfType(ib, IContainer));
        ';
		haxiom.interpret(script54);

		// Test type safety checks for script-side generic fields
		var errorThrownGenericField = false;
		try {
			haxiom.interpret('
                class Box<T> {
                    public var value:T;
                    public function new(v:T) { this.value = v; }
                }
                var b = new Box<Int>(10);
                b.value = "not-an-int";
            ');
		} catch (e:Dynamic) {
			errorThrownGenericField = true;
			trace("Expected generic field type mismatch caught: " + e);
		}
		if (!errorThrownGenericField) {
			throw "FAIL: Expected exception for generic field type mismatch was not thrown.";
		}

		// Test generic class assignment mismatch
		var errorThrownGenericAssign = false;
		try {
			haxiom.interpret('
                class Box<T> {
                    public var value:T;
                    public function new(v:T) { this.value = v; }
                }
                var b = new Box<Int>(10);
                var invalidB:Box<String> = b;
            ');
		} catch (e:Dynamic) {
			errorThrownGenericAssign = true;
			trace("Expected generic assignment mismatch caught: " + e);
		}
		if (!errorThrownGenericAssign) {
			throw "FAIL: Expected exception for generic class assignment mismatch was not thrown.";
		}

		// Test generic interface method signature mismatch (wrong return type)
		var errorThrownGenericItf = false;
		try {
			haxiom.interpret('
                interface IContainer<T> {
                    function getValue():T;
                }
                class BadBox implements IContainer<Int> {
                    public function new() {}
                    public function getValue():String {
                        return "string";
                    }
                }
            ');
		} catch (e:Dynamic) {
			errorThrownGenericItf = true;
			trace("Expected interface method mismatch caught: " + e);
		}
		if (!errorThrownGenericItf) {
			throw "FAIL: Expected exception for generic interface method mismatch was not thrown.";
		}

		// 55. Constant Folding and Scope Pooling Verification
		var ast = haxiom.compile("var a = 2 + 3 * 4; trace(a);");
		switch (ast.def) {
			case EBlock(exprs):
				var first = exprs[0];
				switch (first.def) {
					case EVar(name, type, init, isFinal):
						switch (init.def) {
							case EValue(v):
								if ((v : Dynamic) == 14) {
									trace("SUCCESS: Constant folding optimized 2 + 3 * 4 to 14");
								} else {
									throw "FAIL: Constant folding optimized to " + v + " instead of 14";
								}
							default:
								throw "FAIL: Constant folding did not fold the expression to EValue";
						}
					default:
						throw "FAIL: Expected EVar as first expression in block";
				}
			default:
				throw "FAIL: Expected EBlock from compile";
		}

		var ast2 = haxiom.compile("if (true) { var x = 1; } else { var y = 2; }");
		switch (ast2.def) {
			case EBlock(exprs):
				var first = exprs[0];
				switch (first.def) {
					case EBlock(_):
						trace("SUCCESS: EIf with constant true folded to e1 block successfully");
					default:
						throw "FAIL: EIf constant true was not folded to e1 block: " + first.def;
				}
			default:
				throw "FAIL: Expected EBlock from compile";
		}

		var poolSizeBefore = Scope.pool.length;
		var script55_pool = "
            var sum = 0;
            for (i in 0...100) {
                sum = sum + i;
            }
        ";
		haxiom.interpret(script55_pool);
		var poolSizeAfter = Scope.pool.length;
		trace("Scope pool size before: " + poolSizeBefore + ", after: " + poolSizeAfter);
		if (poolSizeAfter > 0) {
			trace("SUCCESS: Scope pooling successfully recycled scopes.");
		} else {
			throw "FAIL: Scope pooling did not recycle any scopes.";
		}

		var script55_closure = "
            var makeAdder = function(x) {
                return function(y) { return x + y; };
            };
            var add5 = makeAdder(5);
            if (add5(10) != 15) throw 'Closure returned wrong value';
            trace('Closure verification value: ' + add5(10));
        ";
		haxiom.interpret(script55_closure);
		trace("SUCCESS: Closure capture scope pooling check passed.");

		// 56. Native Standard Library Auto-Exposure Verification
		var script56 = "
            import haxe.Timer;
            import haxe.Json;
            
            // Test Date global binding
            var d = Date.now();
            var year = d.getFullYear();
            trace('Date global check year: ' + year);
            if (year < 2020) throw 'Invalid year from Date: ' + year;

            // Test haxe.Json usage
            var jsonStr = '{\"value\": 42}';
            var parsed = Json.parse(jsonStr);
            trace('Json parse value: ' + parsed.value);
            if (parsed.value != 42) throw 'Json parse failed';

            var stringified = Json.stringify(parsed);
            trace('Json stringify output: ' + stringified);

            // Test haxe.Timer usage
            var start = Timer.stamp();
            var end = Timer.stamp();
            trace('Timer stamp diff: ' + (end - start));
        ";
		haxiom.interpret(script56);
		trace("SUCCESS: Native standard library auto-exposure check passed.");

		// 57. Improved Error Reporting Verification
		// A. Lexer Unrecognized Character
		var unrecognizedCharThrown = false;
		try {
			haxiom.interpret("var x = 10 `;");
		} catch (e:haxiom.ScriptException) {
			unrecognizedCharThrown = true;
			if (e.line == 1 && e.col == 12) {
				trace("SUCCESS: Caught lexer unrecognized character error at expected position (line 1, col 12)");
			} else {
				throw "FAIL: Expected lexer unrecognized character error at line 1, col 12, got " + e.line + ":" + e.col;
			}
		}
		if (!unrecognizedCharThrown)
			throw "FAIL: Unrecognized character did not throw";

		// B. Lexer Unclosed String Literal
		var unclosedStringThrown = false;
		try {
			haxiom.interpret("var s = \"hello;");
		} catch (e:haxiom.ScriptException) {
			unclosedStringThrown = true;
			if (e.line == 1 && e.col == 9) {
				trace("SUCCESS: Caught lexer unclosed string error at expected position (line 1, col 9)");
			} else {
				throw "FAIL: Expected lexer unclosed string error at line 1, col 9, got " + e.line + ":" + e.col;
			}
		}
		if (!unclosedStringThrown)
			throw "FAIL: Unclosed string did not throw";

		// C. Parser Expected-Token with Code Frame Verification
		var parserCodeFrameThrown = false;
		try {
			haxiom.interpret("
                var a = 10;
                var b = 10 + ;
                var c = 20;
            ");
		} catch (e:haxiom.ScriptException) {
			parserCodeFrameThrown = true;
			if (e.line == 3 && e.col == 30) {
				trace("SUCCESS: Caught parser syntax error at expected position (line 3, col 30)");
				if (e.message.indexOf(">> ") != -1 && e.message.indexOf("^") != -1) {
					trace("SUCCESS: Parser ScriptException contains visual code frame pointer");
				} else {
					throw "FAIL: Parser ScriptException code frame formatting missing pointer line or highlighting: " + e.message;
				}
			} else {
				throw "FAIL: Expected parser syntax error at line 3, col 30, got " + e.line + ":" + e.col;
			}
		}
		if (!parserCodeFrameThrown)
			throw "FAIL: Parser syntax error did not throw";

		// D. Runtime Error Code Frame Verification
		var runtimeCodeFrameThrown = false;
		try {
			haxiom.interpret("
                var a:Int = 10;
                a = 'not-an-int';
            ");
		} catch (e:haxiom.ScriptException) {
			runtimeCodeFrameThrown = true;
			if (e.message.indexOf(">> ") != -1 && e.message.indexOf("^") != -1) {
				trace("SUCCESS: Runtime ScriptException contains visual code frame pointer");
			} else {
				throw "FAIL: Runtime ScriptException code frame formatting missing pointer line: " + e.message;
			}
		}
		if (!runtimeCodeFrameThrown)
			throw "FAIL: Runtime type mismatch did not throw";

		trace("SUCCESS: Improved error reporting checks passed.");

		// 58. Sandbox and API Exposure Security Verification
		#if sys
		// Force compile sys classes by referencing them in the host code (this test)
		var forceSysFile = sys.io.File;
		var forceSysFS = sys.FileSystem;
		#end

		var testHaxiom = new haxiom.Haxiom();

		// A. Verify Sys is not importable by default
		var sysImportThrown = false;
		try {
			trace("testHaxiom.errorHandler == null: " + (testHaxiom.errorHandler == null));
			trace("testHaxiom.interp.errorHandler == null: " + (testHaxiom.interp.errorHandler == null));
			var ast = testHaxiom.compile("import Sys;");
			trace("Compile AST: " + (ast == null ? "null" : Std.string(ast.def)));
			var res = testHaxiom.execute(ast);
			trace("Sys import execute returned: " + res);
			sysImportThrown = false;
		} catch (e:Dynamic) {
			sysImportThrown = true;
			trace("SUCCESS: Caught expected Sys import blocking: " + e);
			if (Reflect.hasField(e, "message")) {
				trace("Error message: " + Reflect.field(e, "message"));
			}
		}
		if (!sysImportThrown)
			throw "FAIL: Sys import was not blocked by default whitelist";

		// B. Verify fully qualified Sys or sys.io.File access fails by default
		var fqSysAccessThrown = false;
		try {
			testHaxiom.interpret("
                Sys.println('should fail');
            ");
		} catch (e:haxiom.ScriptException) {
			fqSysAccessThrown = true;
			trace("SUCCESS: Caught expected fully-qualified Sys access blocking: " + e.message);
		}
		if (!fqSysAccessThrown)
			throw "FAIL: Fully-qualified Sys access was not blocked";

		var fqFileAccessThrown = false;
		try {
			testHaxiom.interpret("
                var exists = sys.FileSystem.exists('README.md');
            ");
		} catch (e:haxiom.ScriptException) {
			fqFileAccessThrown = true;
			trace("SUCCESS: Caught expected fully-qualified sys.FileSystem blocking: " + e.message);
		}
		if (!fqFileAccessThrown)
			throw "FAIL: Fully-qualified sys.FileSystem access was not blocked";

		// C. Verify Type and Reflect are not available as globals by default
		var typeGlobalThrown = false;
		try {
			testHaxiom.interpret("
                var t = Type.resolveClass('Sys');
            ");
		} catch (e:haxiom.ScriptException) {
			typeGlobalThrown = true;
			trace("SUCCESS: Caught expected global Type reference blocking: " + e.message);
		}
		if (!typeGlobalThrown)
			throw "FAIL: Global Type reference was not blocked by default";

		var reflectGlobalThrown = false;
		try {
			testHaxiom.interpret("
                var f = Reflect.field({}, 'foo');
            ");
		} catch (e:haxiom.ScriptException) {
			reflectGlobalThrown = true;
			trace("SUCCESS: Caught expected global Reflect reference blocking: " + e.message);
		}
		if (!reflectGlobalThrown)
			throw "FAIL: Global Reflect reference was not blocked by default";

		// D. Verify Type / Reflect proxies (when whitelisted/imported) enforce whitelisting
		testHaxiom.importWhitelist.push("Type");
		testHaxiom.importWhitelist.push("Reflect");

		// Dynamic resolution check through Type proxy
		try {
			testHaxiom.interpret("
                import Type;
                var resolved = Type.resolveClass('Sys');
                if (resolved != null) {
                    throw 'Resolved Sys Class even though it was not whitelisted';
                }
            ");
			trace("SUCCESS: Type proxy returned null for non-whitelisted resolveClass");
		} catch (e:Dynamic) {
			throw "FAIL: Type proxy resolveClass did not handle whitelist checks safely: " + e;
		}

		// Reflection call check through Reflect proxy
		var reflectProxyCallBlocked = false;
		try {
			testHaxiom.interpret("
                import Reflect;
                import Type;
                
                // Get a Class that is in the default whitelist
                var mathCls = Type.resolveClass('Math');
                if (mathCls == null) throw 'Could not resolve whitelisted Math';
                
                // Retrieve a non-whitelisted class (should be null)
                var sysCls = Type.resolveClass('Sys');
                
                // Attempt Reflect.callMethod on a non-whitelisted string classname or null reference
                Reflect.callMethod(sysCls, Reflect.field(sysCls, 'println'), ['should fail']);
            ");
		} catch (e:haxiom.ScriptException) {
			reflectProxyCallBlocked = true;
			trace("SUCCESS: Caught expected Reflect proxy call blocking: " + e.message);
		}
		if (!reflectProxyCallBlocked)
			throw "FAIL: Reflect proxy call was not blocked";

		// E. Verify that setting importWhitelist = null turns off sandboxing
		testHaxiom.importWhitelist = null;
		try {
			testHaxiom.interpret("
                import haxiom.FFIClassHelper;
                // If it successfully compiles and interprets, we are good
                trace('SUCCESS: Sandbox disabled successfully (importWhitelist = null)');
            ");
		} catch (e:Dynamic) {
			throw "FAIL: Disabling sandbox with importWhitelist = null threw error: " + e;
		}

		trace("SUCCESS: Sandbox and API exposure security checks passed.");

		// 59. Typedef Declarations and Resolution
		var script59 = "
            typedef Age = Int;
            var x:Age = 25;
            if (x != 25) throw 'Typedef alias assignment failed';

            typedef Point = {x:Int, y:Int};
            var p:Point = {x:10, y:20};
            if (p.x != 10 || p.y != 20) throw 'Typedef structural assignment failed';

            typedef Container<T> = {value:T};
            var c:Container<String> = {value:'hello'};
            if (c.value != 'hello') throw 'Typedef generic assignment failed';
        ";
		haxiom.interpret(script59);
		trace("SUCCESS: Typedef valid assignments passed.");

		var invalidPointThrown = false;
		try {
			haxiom.interpret("
                typedef Point = {x:Int, y:Int};
                var p:Point = {x:10};
            ");
		} catch (e:Dynamic) {
			invalidPointThrown = true;
			trace("SUCCESS: Caught expected typedef Point validation error: " + e);
		}
		if (!invalidPointThrown)
			throw "FAIL: Mismatched anonymous structure typedef did not throw";

		var invalidGenericThrown = false;
		try {
			haxiom.interpret("
                typedef Container<T> = {value:T};
                var c:Container<Int> = {value:'not-an-int'};
            ");
		} catch (e:Dynamic) {
			invalidGenericThrown = true;
			trace("SUCCESS: Caught expected typedef generic parameter validation error: " + e);
		}
		if (!invalidGenericThrown)
			throw "FAIL: Mismatched typedef generic parameter did not throw";

		// 60. Explicit Function Type Validation
		var script60 = "
            var cb:(Int, String)->Bool = function(a:Int, b:String):Bool {
                return true;
            };
            if (cb(5, 'hello') != true) throw 'Function callback execution failed';
        ";
		haxiom.interpret(script60);
		trace("SUCCESS: Function signature valid assignment passed.");

		var invalidArgCountThrown = false;
		try {
			haxiom.interpret("
                var cb:(Int, String)->Bool = function(a:Int):Bool { return true; };
            ");
		} catch (e:Dynamic) {
			invalidArgCountThrown = true;
			trace("SUCCESS: Caught expected function argument count mismatch: " + e);
		}
		if (!invalidArgCountThrown)
			throw "FAIL: Mismatched function argument count did not throw";

		var invalidArgTypeThrown = false;
		try {
			haxiom.interpret("
                var cb:(Int, String)->Bool = function(a:String, b:String):Bool { return true; };
            ");
		} catch (e:Dynamic) {
			invalidArgTypeThrown = true;
			trace("SUCCESS: Caught expected function argument type mismatch: " + e);
		}
		if (!invalidArgTypeThrown)
			throw "FAIL: Mismatched function argument type did not throw";

		var invalidReturnTypeThrown = false;
		try {
			haxiom.interpret("
                var cb:(Int, String)->Bool = function(a:Int, b:String):String { return 'test'; };
            ");
		} catch (e:Dynamic) {
			invalidReturnTypeThrown = true;
			trace("SUCCESS: Caught expected function return type mismatch: " + e);
		}
		if (!invalidReturnTypeThrown)
			throw "FAIL: Mismatched function return type did not throw";
	}

	static function runPart4(haxiom:haxiom.Haxiom) {
		// 61. AST Caching Verification
		var testCacheHaxiom = new haxiom.Haxiom();
		testCacheHaxiom.enableAstCache = true;
		var src = "var cacheTest = 100;";
		var ast1 = testCacheHaxiom.compile(src);
		var ast2 = testCacheHaxiom.compile(src);
		if (ast1 != ast2) {
			throw "FAIL: AST Caching failed to return cached AST reference";
		}
		trace("SUCCESS: AST Caching returned identical AST reference on repeat compile");

		// Test caching disabled
		testCacheHaxiom.enableAstCache = false;
		var ast3 = testCacheHaxiom.compile(src);
		if (ast1 == ast3) {
			throw "FAIL: AST Caching returned cached AST reference even when disabled";
		}
		trace("SUCCESS: AST Caching disabled check passed");

		// Test capacity eviction (1000 items)
		var testCacheHaxiom2 = new haxiom.Haxiom();
		testCacheHaxiom2.enableAstCache = true;
		var preEvictAst = testCacheHaxiom2.compile("var x = 1000;");
		for (i in 0...999) {
			testCacheHaxiom2.compile("var x = " + i + ";");
		}
		testCacheHaxiom2.compile("var x = 1001;");
		var postEvictAst = testCacheHaxiom2.compile("var x = 1000;");
		if (preEvictAst == postEvictAst) {
			throw "FAIL: AST Cache capacity eviction did not clear the cache";
		}
		trace("SUCCESS: AST Cache capacity eviction verified successfully");

		// 62. Expanded Stdlib Mapping
		var testStdHaxiom = new haxiom.Haxiom();

		var accessJsonWithoutImportThrown = false;
		try {
			testStdHaxiom.interpret("
                var parsed = Json.parse('{\"x\":1}');
            ");
		} catch (e:Dynamic) {
			accessJsonWithoutImportThrown = true;
			trace("SUCCESS: Caught expected Json access without import error: " + e);
		}
		if (!accessJsonWithoutImportThrown)
			throw "FAIL: Accessing Json without import did not throw";

		var accessStringBufWithoutImportThrown = false;
		try {
			testStdHaxiom.interpret("
                var buf = new StringBuf();
            ");
		} catch (e:Dynamic) {
			accessStringBufWithoutImportThrown = true;
			trace("SUCCESS: Caught expected StringBuf access without import error: " + e);
		}
		if (!accessStringBufWithoutImportThrown)
			throw "FAIL: Accessing StringBuf without import did not throw";

		var script62_success = "
            import haxe.Json;
            import haxe.Timer;
            import StringBuf;
            import haxe.io.Bytes;
            import haxe.io.Path;

            var parsed = Json.parse('{\"value\": 100}');
            if (parsed.value != 100) throw 'Json value mismatch';

            var stamp = Timer.stamp();

            var buf = new StringBuf();
            buf.add('hello');
            buf.add(' world');
            if (buf.toString() != 'hello world') throw 'StringBuf value mismatch';

            var bytes = Bytes.ofString('haxiom');
            if (bytes.getString(0, 6) != 'haxiom') throw 'Bytes value mismatch';

            var path = new Path('/some/file.txt');
            if (path.ext != 'txt') throw 'Path extension mismatch';
        ";
		testStdHaxiom.interpret(script62_success);
		trace("SUCCESS: Manually imported standard library classes work correctly");

		// 63. Script-Side Property Getters/Setters Verification
		var script63 = "
            class TestProperties {
                public var x(get, set):Int;
                var _x:Int = 0;
                public function get_x():Int {
                    return _x;
                }
                public function set_x(v:Int):Int {
                    _x = v;
                    return _x;
                }

                // Testing recursion protection
                public var recursiveProp(get, set):Int;
                var _rec:Int = 10;
                public function get_recursiveProp():Int {
                    return recursiveProp;
                }
                public function set_recursiveProp(v:Int):Int {
                    recursiveProp = v;
                    return recursiveProp;
                }

                // default, set
                public var y(default, set):Int;
                public function set_y(v:Int):Int {
                    y = v + 1;
                    return y;
                }

                // get, null
                public var z(get, null):Int;
                var _z:Int = 99;
                public function get_z():Int {
                    return _z;
                }
                
                public function new() {
                    recursiveProp = 10;
                }
            }

            var t = new TestProperties();
            
            // 1. Get/Set redirection
            t.x = 42;
            if (t.x != 42) throw 'Property get/set redirection failed';

            // 2. Recursion protection check
            if (t.recursiveProp != 10) throw 'Property read inside getter recursive loop failed';
            t.recursiveProp = 55;
            if (t.recursiveProp != 55) throw 'Property write inside setter recursive loop failed';

            // 3. Default, set check
            t.y = 100;
            if (t.y != 101) throw 'Property default, set failed';

            // 4. Get, null check
            if (t.z != 99) throw 'Property get, null read failed';
        ";
		haxiom.interpret(script63);
		trace("SUCCESS: Valid property read/write and recursion protection passed.");

		var nullSetterBlocked = false;
		try {
			haxiom.interpret("
                class TestProp {
                    public var val(default, null):Int = 10;
                }
                var p = new TestProp();
                p.val = 20;
            ");
		} catch (e:Dynamic) {
			nullSetterBlocked = true;
			trace("SUCCESS: Caught expected null setter write blocking: " + e);
		}
		if (!nullSetterBlocked)
			throw "FAIL: Null setter write was not blocked from outside the class";

		// 64. Properties on Interfaces
		var script64_success = "
            interface IWithProp {
                var val(get, set):Int;
                var normalVar:String;
            }
            class ImplClass implements IWithProp {
                public var val(get, set):Int;
                var _val:Int = 0;
                public function get_val():Int { return _val; }
                public function set_val(v:Int):Int { _val = v; return _val; }
                
                public var normalVar:String;
                public function new() {}
            }
            var obj:IWithProp = new ImplClass();
            obj.val = 123;
            if (obj.val != 123) throw 'Interface property set/get failed';
        ";
		haxiom.interpret(script64_success);
		trace("SUCCESS: Implementing interface with property and variables succeeded.");

		var interfacePropMismatch = false;
		try {
			haxiom.interpret("
                interface IWithProp {
                    var val(get, set):Int;
                }
                class ImplMismatch implements IWithProp {
                    public var val:Int;
                    public function new() {}
                }
            ");
		} catch (e:Dynamic) {
			interfacePropMismatch = true;
			trace("SUCCESS: Interface property mismatch caught: " + e);
		}
		if (!interfacePropMismatch)
			throw "FAIL: Mismatch in property vs variable implementing interface was not caught";

		// 65. Metadata Parsing & Reflection
		var script65 = "
            import haxe.rtti.Meta;

            @:myMeta(42, 'hello')
            class AnnotatedClass {
                @:fieldMeta('field')
                public var myField:Int;

                @:methodMeta('method')
                public function myMethod() {}

                @:staticMeta('static')
                public static var staticField:Int;
            }

            var typeMeta = Meta.getType(AnnotatedClass);
            if (typeMeta.myMeta == null || typeMeta.myMeta[0] != 42 || typeMeta.myMeta[1] != 'hello') {
                throw 'Class metadata lookup failed';
            }

            var fieldsMeta = Meta.getFields(AnnotatedClass);
            if (fieldsMeta.myField.fieldMeta[0] != 'field' || fieldsMeta.myMethod.methodMeta[0] != 'method') {
                throw 'Fields/methods metadata lookup failed';
            }

            var staticsMeta = Meta.getStatics(AnnotatedClass);
            if (staticsMeta.staticField.staticMeta[0] != 'static') {
                throw 'Statics metadata lookup failed';
            }
        ";
		haxiom.interpret(script65);
		trace("SUCCESS: Metadata parsing & reflection (Meta API) passed.");

		// 66. Safe Cast & Unsafe Cast
		var script66 = "
            class Animal { public function new() {} }
            class Dog extends Animal { public function new() { super(); } }
            class Cat extends Animal { public function new() { super(); } }

            var d:Animal = new Dog();
            var dog:Dog = cast(d, Dog);

            var isCastError = false;
            try {
                var cat:Cat = cast(d, Cat);
            } catch (e:Dynamic) {
                isCastError = true;
            }
            if (!isCastError) throw 'Expected cast error for invalid cast';

            var dogRaw:Dynamic = cast d;
        ";
		haxiom.interpret(script66);
		trace("SUCCESS: Safe and unsafe casts verified.");

		// 67. Cross-Platform Stdlib & Explicit Imports
		var script67_success = "
            import haxe.crypto.Md5;
            import haxe.ds.Vector;
            import haxe.Exception;

            var md5 = Md5.encode('haxiom');
            if (md5 != '6eb6d8292170904ff8479e7def6b2a0d') throw 'Md5 encode mismatch';

            var vec = new Vector<Int>(5);
            vec[0] = 99;
            if (vec[0] != 99) throw 'Vector value mismatch';

            var ex = new Exception('test exception');
            if (ex.message != 'test exception') throw 'Exception message mismatch';
        ";
		haxiom.interpret(script67_success);

		var script67_wildcard = "
            import haxe.crypto.*;
            var sha1 = Sha1.encode('haxiom');
            if (sha1 != '71595298aa823686677b3b0d3278b353f2d89d6c') throw 'Sha1 wildcard encode mismatch';
        ";
		haxiom.interpret(script67_wildcard);

		var accessNoImportFailed = false;
		try {
			var freshHaxiom = new haxiom.Haxiom();
			freshHaxiom.interpret("
                var md5 = haxe.crypto.Md5.encode('test');
            ");
		} catch (e:Dynamic) {
			accessNoImportFailed = true;
			trace("SUCCESS: Blocked access to haxe.crypto.Md5 without explicit import: " + e);
		}
		if (!accessNoImportFailed)
			throw "FAIL: Accessing native class without import was not blocked";
		trace("SUCCESS: Cross-platform stdlib packages with explicit/wildcard imports work correctly.");

		// 68. Advanced Switch Pattern Matching
		var script68 = "
            enum Animal {
                Dog(name:String, age:Int);
                Cat(name:String);
                Bird;
            }

            function testPattern(a:Animal):String {
                switch (a) {
                    case Dog('Rex', 1 | 2):
                        return 'Young Rex';
                    case Dog(name, 5 | 10):
                        return name + ' is older';
                    case Cat('Garfield' | 'Tom'):
                        return 'Famous Cat';
                    case Cat(name) if (name == 'Sylvester'):
                        return 'Sylvester';
                    case _.toString() => 'Bird':
                        return 'Bird Extractor';
                    default:
                        return 'Other';
                }
            }

            if (testPattern(Dog('Rex', 2)) != 'Young Rex') throw 'Rex age 2 mismatch';
            if (testPattern(Dog('Rex', 3)) != 'Other') throw 'Rex age 3 mismatch';
            if (testPattern(Dog('Max', 10)) != 'Max is older') throw 'Max age 10 mismatch';
            if (testPattern(Cat('Tom')) != 'Famous Cat') throw 'Tom mismatch';
            if (testPattern(Cat('Felix')) != 'Other') throw 'Felix mismatch';
            if (testPattern(Bird) != 'Bird Extractor') throw 'Bird extractor mismatch';
        ";
		haxiom.interpret(script68);
		trace("SUCCESS: Advanced Switch Pattern Matching (Or-patterns, extractors) verified.");

		// 69. Abstract Operator Overloading
		var script69 = "
            abstract MyInt(Int) {
                public function new(v:Int) {
                    this = v;
                }
                public function getValue():Int {
                    return this;
                }
                @:op(A + B)
                public static function add(a:MyInt, b:MyInt):MyInt {
                    return new MyInt(a.getValue() + b.getValue());
                }
                @:op(A * B)
                public static function multiply(a:MyInt, b:Int):MyInt {
                    return new MyInt(a.getValue() * b);
                }
                @:op(-A)
                public static function negate(a:MyInt):MyInt {
                    return new MyInt(-a.getValue());
                }
                @:op(++A)
                public static function preIncrement(a:MyInt):MyInt {
                    return new MyInt(a.getValue() + 1);
                }
                @:op(A++)
                public static function postIncrement(a:MyInt):MyInt {
                    return new MyInt(a.getValue() + 1);
                }
            }

            var x = new MyInt(10);
            var y = new MyInt(5);
            var z = x + y;
            if (z.getValue() != 15) throw 'Overloaded binary + failed';

            var z2 = x * 3;
            if (z2.getValue() != 30) throw 'Overloaded binary * failed';

            var z3 = -x;
            if (z3.getValue() != -10) throw 'Overloaded unary - failed';

            var w = new MyInt(20);
            var pre = ++w;
            if (pre.getValue() != 21 || w.getValue() != 21) throw 'Overloaded prefix ++ failed';

            var post = w++;
            if (post.getValue() != 21 || w.getValue() != 22) throw 'Overloaded postfix ++ failed';
        ";
		haxiom.interpret(script69);
		trace("SUCCESS: Abstract Operator Overloading verified.");

		// 70. AST Serialization & Deserialization
		var script70 = "
            abstract MyInt(Int) {
                public function new(v:Int) {
                    this = v;
                }
                public function getValue():Int {
                    return this;
                }
                @:op(A + B)
                public static function add(a:MyInt, b:MyInt):MyInt {
                    return new MyInt(a.getValue() + b.getValue());
                }
            }
            var a = new MyInt(100);
            var b = new MyInt(200);
            var c = a + b;
            c.getValue();
        ";
		var bytes = haxiom.compileToBytes(script70);
		if (bytes == null || bytes.length == 0)
			throw "Failed to compile to bytes";

		var freshHaxiom = new haxiom.Haxiom();
		var result:Int = freshHaxiom.executeBytes(bytes);
		if (result != 300)
			throw "Serialization execution result mismatch: " + result;

		// Test error position recovery from deserialized bytes
		var script70_error = "
            var a = 10;
            var b = 0;
            var c = a / b;
            throw 'Explicit Error!';
        ";
		var errorBytes = haxiom.compileToBytes(script70_error);
		var errorHaxiom = new haxiom.Haxiom();
		var errorOccurred = false;
		try {
			errorHaxiom.executeBytes(errorBytes, script70_error);
		} catch (e:haxiom.ScriptException) {
			errorOccurred = true;
			if (e.line != 5)
				throw "Expected error on line 5 but got: " + e.line;
			if (e.message.indexOf("throw 'Explicit Error!'") == -1) {
				throw "Expected code frame with source line but got: " + e.message;
			}
		}
		if (!errorOccurred)
			throw "Expected error during execution of errorBytes, but none occurred";
		trace("SUCCESS: AST Serialization & Deserialization verified.");

		// 71. VM Execution Mode Verification
		var vmEngine = new haxiom.Haxiom();
		vmEngine.useVM = true;

		var script71 = "
            // 1. Arithmetic & variables
            var a = 100;
            var b = 200;
            var c = (a + b) * 3 / 2 % 100; // 300 * 3 / 2 = 450. 450 % 100 = 50
            
            // 2. Local variables and mutated increments
            var x = 10;
            var pre = ++x; // pre = 11, x = 11
            var post = x++; // post = 11, x = 12
            
            // 3. Conditionals and Loops
            var sum = 0;
            for (i in 0...5) {
                sum += i;
            } // sum = 0 + 1 + 2 + 3 + 4 = 10
            
            var j = 0;
            var whileSum = 0;
            while (j < 3) {
                j++;
                if (j == 2) continue;
                whileSum += j;
            } // j=1: whileSum=1. j=2: skipped. j=3: whileSum=1+3=4
            
            // 4. Switch pattern matching
            var switchRes = 'none';
            var val = 42;
            switch (val) {
                case 10: switchRes = 'ten';
                case 42 if (a == 100): switchRes = 'forty-two';
                default: switchRes = 'def';
            }
            
            // 5. Array & Map declarators & subscripting
            var arr = [10, 20, 30];
            arr[1] = 99;
            var arrVal = arr[0] + arr[1] + arr[2]; // 10 + 99 + 30 = 139
            
            var map = ['x' => 1, 'y' => 2];
            map['z'] = 3;
            var mapVal = map['x'] + map['y'] + map['z']; // 1 + 2 + 3 = 6
            
            // 6. Closures
            var multiplier = (factor) -> {
                return (val) -> val * factor;
            };
            var timesTen = multiplier(10);
            var closureRes = timesTen(5); // 50
            
            // 7. Try-Catch exception handling
            var caughtMessage = 'none';
            try {
                throw 'Custom Error!';
            } catch (err:String) {
                caughtMessage = err;
            }
            
            // Return struct containing verification results
            var resStruct = {
                c: c,
                pre: pre,
                post: post,
                x: x,
                sum: sum,
                whileSum: whileSum,
                switchRes: switchRes,
                arrVal: arrVal,
                mapVal: mapVal,
                closureRes: closureRes,
                caughtMessage: caughtMessage
            };
            resStruct;
        ";

		var vmResult:Dynamic = vmEngine.interpret(script71);
		if (vmResult.c != 50)
			throw "VM arithmetic/ops failed: " + vmResult.c;
		if (vmResult.pre != 11 || vmResult.post != 11 || vmResult.x != 12)
			throw "VM mutating unops failed";
		if (vmResult.sum != 10)
			throw "VM for-loop failed: " + vmResult.sum;
		if (vmResult.whileSum != 4)
			throw "VM while-loop with continue failed: " + vmResult.whileSum;
		if (vmResult.switchRes != "forty-two")
			throw "VM switch pattern matching failed";
		if (vmResult.arrVal != 139)
			throw "VM array subscript read/write failed: " + vmResult.arrVal;
		if (vmResult.mapVal != 6)
			throw "VM map/subscript failed: " + vmResult.mapVal;
		if (vmResult.closureRes != 50)
			throw "VM closure failed: " + vmResult.closureRes;
		if (vmResult.caughtMessage != "Custom Error!")
			throw "VM try-catch exception handling failed";

		// 8. Test error position recovery inside VM
		var script71_error = "
            var a = 10;
            var b = 0;
            var c = a / b;
            throw 'VM Explicit Error!';
        ";
		var errEngine = new haxiom.Haxiom();
		errEngine.useVM = true;
		var errorOccurred = false;
		try {
			errEngine.interpret(script71_error);
		} catch (e:haxiom.ScriptException) {
			errorOccurred = true;
			if (e.line != 5)
				throw "VM Expected error on line 5 but got: " + e.line;
			if (e.message.indexOf("throw 'VM Explicit Error!'") == -1) {
				throw "VM Expected code frame with source line but got: " + e.message;
			}
		}
		if (!errorOccurred)
			throw "Expected VM runtime error, but none occurred";
		trace("SUCCESS: VM Execution Mode verified.");

		// 72. Bytecode & AST Persistence Verification
		var persistEngine = new haxiom.Haxiom();

		var script72 = "
            var factor = 5;
            var closure = (x) -> x * factor;
            var sum = 0;
            for (i in 1...4) {
                sum += closure(i);
            }
            var switchRes = 'none';
            var val = 100;
            switch (val) {
                case 100 if (factor == 5): switchRes = 'hundred';
                default: switchRes = 'other';
            }
            var res = { sum: sum, switchRes: switchRes };
            res;
        ";

		// 1. AST Persistence Test
		var astBytes = persistEngine.compileToASTBytes(script72);
		if (astBytes == null)
			throw "Failed to compile AST to bytes";

		var astLoaderEngine = new haxiom.Haxiom();
		var astResult:Dynamic = astLoaderEngine.executeASTBytes(astBytes);
		if (astResult.sum != 30)
			throw "AST persistence execution failed: sum=" + astResult.sum;
		if (astResult.switchRes != "hundred")
			throw "AST persistence execution failed: switchRes=" + astResult.switchRes;

		// 2. Bytecode Persistence Test
		var bytecodeBytes = persistEngine.compileToBytecodeBytes(script72);
		if (bytecodeBytes == null)
			throw "Failed to compile Bytecode to bytes";

		var bcLoaderEngine = new haxiom.Haxiom();
		bcLoaderEngine.useVM = true;

		// Verify HXBC magic header
		var headerStr = bytecodeBytes.getString(0, 4);
		if (headerStr != "HXBC") {
			throw "Bytecode persistence failed: expected magic HXBC header, got " + headerStr;
		}

		// Verify version byte
		var verByte = bytecodeBytes.get(4);
		if (verByte != 1) {
			throw "Bytecode persistence failed: expected version 1, got " + verByte;
		}

		// Verify checksum validation on corrupted data
		var corruptedBytes = haxe.io.Bytes.alloc(bytecodeBytes.length);
		corruptedBytes.blit(0, bytecodeBytes, 0, bytecodeBytes.length);
		if (bytecodeBytes.length > 13) {
			corruptedBytes.set(bytecodeBytes.length - 1, corruptedBytes.get(bytecodeBytes.length - 1) ^ 0xAA);
		}

		var checksumErrorOccurred = false;
		try {
			bcLoaderEngine.executeBytecodeBytes(corruptedBytes);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("checksum verification failed") != -1) {
				checksumErrorOccurred = true;
			}
		}
		if (!checksumErrorOccurred)
			throw "Expected bytecode checksum verification error on corrupted bytes, but none occurred";

		var bcResult:Dynamic = bcLoaderEngine.executeBytecodeBytes(bytecodeBytes);
		if (bcResult.sum != 30)
			throw "Bytecode persistence execution failed: sum=" + bcResult.sum;
		if (bcResult.switchRes != "hundred")
			throw "Bytecode persistence execution failed: switchRes=" + bcResult.switchRes;

		// Verify BytecodeChunk.getBytes() and BytecodeChunk.fromBytes() direct APIs
		var ast72 = bcLoaderEngine.compile(script72);
		var chunk72 = BytecodeCompiler.compile(ast72);
		var chunkBytes = chunk72.getBytes();
		var deserializedChunk = VM.BytecodeChunk.fromBytes(chunkBytes);
		var directResult = bcLoaderEngine.interp.executeChunk(deserializedChunk);
		if (directResult.sum != 30)
			throw "Direct getBytes/fromBytes execution failed: sum=" + directResult.sum;
		if (directResult.switchRes != "hundred")
			throw "Direct getBytes/fromBytes execution failed: switchRes=" + directResult.switchRes;

		// 3. VM Bytecode Error Recovery Test
		var script72_error = "
            var a = 200;
            throw 'Bytecode Explicit Error!';
        ";
		var errCompileEngine = new haxiom.Haxiom();
		var errBytes = errCompileEngine.compileToBytecodeBytes(script72_error, "error_bytecode.hx", null, true);

		var errRunEngine = new haxiom.Haxiom();
		errRunEngine.useVM = true;
		var persistErrorOccurred = false;
		try {
			errRunEngine.executeBytecodeBytes(errBytes, script72_error);
		} catch (e:haxiom.ScriptException) {
			persistErrorOccurred = true;
			if (e.line != 3)
				throw "Bytecode persistence expected error on line 3 but got: " + e.line;
			if (e.file != "error_bytecode.hx")
				throw "Bytecode persistence expected file name error_bytecode.hx but got: " + e.file;
			if (e.message.indexOf("throw 'Bytecode Explicit Error!'") == -1) {
				throw "Bytecode persistence expected code frame with source line but got: " + e.message;
			}
		}
		if (!persistErrorOccurred)
			throw "Expected bytecode runtime error, but none occurred";
		trace("SUCCESS: Bytecode & AST Persistence verified.");

		// 73. VM Class, Constructor, Method, and Property Parity Verification
		var vmClassEngine = new haxiom.Haxiom();
		vmClassEngine.useVM = true;

		var script73 = "
            class Animal {
                public var name:String;
                public function new(name:String) {
                    this.name = name;
                }
                public function greet():String {
                    return 'Animal:' + this.name;
                }
            }

            class Dog extends Animal {
                public var breed:String;
                public var barkCount:Int = 0;
                
                public function new(name:String, breed:String) {
                    super(name);
                    this.breed = breed;
                }
                
                public function greet():String {
                    return 'Dog:' + this.name + ' (' + this.breed + ')';
                }
                
                public var fullTitle(get, set):String;
                public function get_fullTitle():String {
                    return this.greet() + ' (barkCount=' + this.barkCount + ')';
                }
                public function set_fullTitle(val:String):String {
                    this.barkCount++;
                    return val;
                }
            }

            var d = new Dog('Buddy', 'Golden Retriever');
            var firstGreet = d.greet();
            var titleBefore = d.fullTitle;
            d.fullTitle = 'Test';
            var titleAfter = d.fullTitle;
            
            var out = {
                firstGreet: firstGreet,
                titleBefore: titleBefore,
                titleAfter: titleAfter,
                barkCount: d.barkCount
            };
            out;
        ";

		var result73:Dynamic = vmClassEngine.interpret(script73);
		if (result73.firstGreet != "Dog:Buddy (Golden Retriever)")
			throw "VM Class parity failed: firstGreet=" + result73.firstGreet;
		if (result73.titleBefore != "Dog:Buddy (Golden Retriever) (barkCount=0)")
			throw "VM Class parity failed: titleBefore=" + result73.titleBefore;
		if (result73.barkCount != 1)
			throw "VM Class parity failed: barkCount=" + result73.barkCount;
		if (result73.titleAfter != "Dog:Buddy (Golden Retriever) (barkCount=1)")
			throw "VM Class parity failed: titleAfter=" + result73.titleAfter;

		var script73_error = "
            class ErrorProducer {
                public function new() {}
                public function fail():Void {
                    throw 'Explicit Method Error!';
                }
            }
            var p = new ErrorProducer();
            p.fail();
        ";
		var errEngine73 = new haxiom.Haxiom();
		errEngine73.useVM = true;
		var errOccurred73 = false;
		try {
			var ast = errEngine73.compile(script73_error, "error_producer.hx");
			errEngine73.execute(ast);
		} catch (e:haxiom.ScriptException) {
			errOccurred73 = true;
			if (e.line != 5)
				throw "VM Class method error expected line 5 but got: " + e.line;
			if (e.file != "error_producer.hx")
				throw "VM Class method error expected file error_producer.hx but got: " + e.file;
			if (e.message.indexOf("throw 'Explicit Method Error!'") == -1) {
				throw "VM Class method error expected code frame with source line but got: " + e.message;
			}
		}
		if (!errOccurred73)
			throw "Expected VM class method runtime error, but none occurred";
		trace("SUCCESS: VM Class, Constructor, Method, and Property Parity verified.");

		// Test 74: VM compile-time slot resolution, slot reuse, shadowing, closures, and variable type validation.
		var vmEngine74 = new haxiom.Haxiom();
		vmEngine74.useVM = true;

		// 1. Slot Reuse Verification
		var script74_1 = "
            class SlotTester {
                public function new() {}
                public function run():Int {
                    {
                        var a:Int = 10;
                    }
                    {
                        var b:Int = 20;
                        return b;
                    }
                }
            }
            new SlotTester().run();
        ";
		var result74_1 = vmEngine74.interpret(script74_1);
		if (result74_1 != 20)
			throw "SlotTester run failed: " + result74_1;

		var slotTesterClass:haxiom.Interp.HaxiomClass = cast vmEngine74.interp.globals.get("SlotTester");
		var runMethod:Dynamic = slotTesterClass.methods.get("run");
		var chunk:haxiom.VM.BytecodeChunk = runMethod.bytecodeChunk;
		// With slot reuse, both local variables a and b reuse slot 0, so maxSlots is 1.
		if (chunk.maxSlots != 1) {
			throw "Slot reuse failed: expected maxSlots == 1, but got " + chunk.maxSlots;
		}

		// 2. Shadowing Verification
		var script74_2 = "
            class ShadowTester {
                public function new() {}
                public function run():Int {
                    var x = 10;
                    {
                        var x = 20;
                        if (x != 20) return 99;
                    }
                    return x;
                }
            }
            new ShadowTester().run();
        ";
		var result74_2 = vmEngine74.interpret(script74_2);
		if (result74_2 != 10)
			throw "Shadowing failed: expected 10, got " + result74_2;

		// 3. Closure Variable Fallback Verification
		var script74_3 = "
            class ClosureTester {
                public function new() {}
                public function run():Int {
                    var x = 10;
                    var f = function():Int {
                        return x;
                    };
                    x = 20;
                    return f();
                }
            }
            new ClosureTester().run();
        ";
		var result74_3 = vmEngine74.interpret(script74_3);
		if (result74_3 != 20)
			throw "Closure variable fallback failed: expected 20, got " + result74_3;

		// 4. Type Checking Validation
		var script74_4 = "
            class TypeTester {
                public function new() {}
                public function run():Int {
                    var x:Int = 10;
                    x = 'hello';
                    return x;
                }
            }
            new TypeTester().run();
        ";
		var errEngine74 = new haxiom.Haxiom();
		errEngine74.useVM = true;
		var typeErrorOccurred = false;
		try {
			errEngine74.interpret(script74_4);
		} catch (e:Dynamic) {
			typeErrorOccurred = true;
		}
		if (!typeErrorOccurred)
			throw "Expected type check error, but none occurred";

		trace("SUCCESS: VM compile-time slot resolution, slot reuse, shadowing, closures, and variable type validation verified.");

		// Test 75: Bytecode Verification & Safety Checks
		var verEngine = new haxiom.Haxiom();

		// 1. Get a valid compiled bytecode bytes
		var validScript = "var x = 10; x + 5;";
		var validBytes = verEngine.compileToBytecodeBytes(validScript);

		// Deserializing valid bytes should succeed
		var validChunk = Serializer.deserializeBytecode(validBytes);

		// Test invalid opcode check
		var invalidOpcodeChunk = new haxiom.VM.BytecodeChunk([99], [], [], 0);
		var invalidOpcodeCaught = false;
		try {
			BytecodeVerifier.verify(invalidOpcodeChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Invalid opcode") != -1) {
				invalidOpcodeCaught = true;
			}
		}
		if (!invalidOpcodeCaught)
			throw "Expected verification error for invalid opcode, but none occurred";

		// Test out-of-bounds constant index check
		var invalidConstChunk = new haxiom.VM.BytecodeChunk([1, 5], [], [], 0);
		var invalidConstCaught = false;
		try {
			BytecodeVerifier.verify(invalidConstChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Constant index") != -1) {
				invalidConstCaught = true;
			}
		}
		if (!invalidConstCaught)
			throw "Expected verification error for out-of-bounds constant, but none occurred";

		// Test out-of-bounds local slot index check
		var invalidSlotChunk = new haxiom.VM.BytecodeChunk([2, 5], [], [], 2);
		var invalidSlotCaught = false;
		try {
			BytecodeVerifier.verify(invalidSlotChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Local slot index") != -1) {
				invalidSlotCaught = true;
			}
		}
		if (!invalidSlotCaught)
			throw "Expected verification error for out-of-bounds slot, but none occurred";

		// Test out-of-bounds jump target check
		var invalidJumpChunk = new haxiom.VM.BytecodeChunk([28, 50], [], [], 0);
		var invalidJumpCaught = false;
		try {
			BytecodeVerifier.verify(invalidJumpChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Jump target") != -1) {
				invalidJumpCaught = true;
			}
		}
		if (!invalidJumpCaught)
			throw "Expected verification error for out-of-bounds jump, but none occurred";

		// 65. Abstract Implicit Casting (from/to) Verification
		var script65 = "
			@:from(Int)
			@:to(Int)
			abstract MyInt(Int) {
				public function new(v:Int) {
					this = v;
				}
			}

			// Variable declaration implicit from-cast
			var x:MyInt = 42;
			// Variable assignment implicit to-cast
			var y:Int = x;
			if (y != 42) throw 'Abstract implicit variable casts failed';

			// Function arguments/returns check
			function testArgAndRet(v:MyInt):MyInt {
				return v;
			}
			var res:Int = testArgAndRet(100);
			if (res != 100) throw 'Function arg/return abstract casts failed';

			// Class fields check
			class Container {
				public var val:MyInt;
				public function new() {}
			}
			var c = new Container();
			c.val = 300;
			var rawVal:Int = c.val;
			if (rawVal != 300) throw 'Class field abstract casts failed';
		";
		haxiom.interpret(script65);
		trace("SUCCESS: Abstract implicit from/to casting verified.");

		// 66. Namespace-scoped Enums & Short Constructor Patterns Verification
		var script66_decl = "
			package test.enums;
			enum Color {
				Red;
				Green;
				Blue;
				Custom(rgb:Int);
			}
		";
		haxiom.interpret(script66_decl);

		var script66_test = "
			import test.enums.Color;

			var c1 = Color.Red;
			var c2 = Color.Custom(0xFF0000);

			var match1 = '';
			switch (c1) {
				case Color.Red: match1 = 'is red';
				case Color.Green: match1 = 'is green';
				default: match1 = 'other';
			}
			if (match1 != 'is red') throw 'Namespaced constant constructor match failed';

			// Test namespaced parameter constructor match
			var match2 = '';
			switch (c2) {
				case Color.Custom(val): match2 = 'custom ' + val;
				default: match2 = 'other';
			}
			if (match2 != 'custom 16711680') throw 'Namespaced parameter constructor match failed';

			// Test fully qualified path constructor match
			var match3 = '';
			switch (c1) {
				case test.enums.Color.Red: match3 = 'is fq red';
				default: match3 = 'other';
			}
			if (match3 != 'is fq red') throw 'Fully qualified constant constructor match failed';

			// Test short constructor identifier match
			var match4 = '';
			switch (c1) {
				case Red: match4 = 'is local red';
				default: match4 = 'other';
			}
			if (match4 != 'is local red') throw 'Short identifier constructor match failed';
		";
		haxiom.interpret(script66_test);
		trace("SUCCESS: Namespace-scoped enums and short constructors pattern matching verified.");

		trace("SUCCESS: Bytecode Verification & Safety Checks verified.");
	}

	static function expectError(haxiom:haxiom.Haxiom, script:String, expectedSnippet:String, label:String) {
		try {
			haxiom.interpret(script);
			throw 'FAIL: ${label} did not throw an exception';
		} catch (e:Dynamic) {
			var errStr = Std.string(e);
			if (errStr.indexOf(expectedSnippet) == -1) {
				throw 'FAIL: ${label} expected exception containing "${expectedSnippet}" but got: ${errStr}';
			}
			var firstLine = errStr.split("\n")[0];
			trace('SUCCESS: Caught expected validation error for ${label}: ${firstLine}');
		}
	}
}

class FFIClassHelper {
	public var factor:Int;

	public function new(factor:Int) {
		this.factor = factor;
	}

	public function multiply(v:Int):Int {
		return v * factor;
	}
}

@:haxiom.expose
class ExposedNativeClass {
	public var multiplier:Int;

	public function new(multiplier:Int) {
		this.multiplier = multiplier;
	}

	public function multiply(v:Int):Int {
		return v * multiplier;
	}
}

@:keep
@:haxiom.expose
abstract WrappedInt(Int) {
	public inline function new(val:Int) {
		this = val;
	}

	public function getValue():Int {
		return this;
	}

	public function multiply(factor:Int):Int {
		return this * factor;
	}

	public var double(get, never):Int;

	inline function get_double():Int {
		return this * 2;
	}
}

@:haxiom.expose
@:generic
class GenericPair<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function getValue():T {
		return value;
	}
}

@:haxiom.expose
class MyIntExtensions {
	public static function doubleVal(v:Int):Int {
		return v * 2;
	}
}
