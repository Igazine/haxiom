package haxiom;

class TestCallerIdentification {
	public static function runTests():Void {
		trace("Starting Host Script Caller Identification (engine.currentCaller) Suite...");

		// Test 1: Native Host Call returns null
		var engine = new Haxiom();
		if (engine.currentCaller != null) {
			throw "Test 1 Failed: Expected engine.currentCaller to be null for native host call";
		}
		trace("SUCCESS: Native host call returned null for currentCaller.");

		// Test 2: AST Mode Script Call Context Identification
		var capturedCallerAST:ScriptStackFrame = null;
		engine.exposeValue("hostLog", function(msg:String) {
			capturedCallerAST = engine.currentCaller;
		});

		var scriptAST = '
            class TestScriptAST {
                public static function run() {
                    hostLog("Hello from AST");
                }
            }
        ';
		engine.interpret(scriptAST);
		engine.interpret("TestScriptAST.run();");

		if (capturedCallerAST == null) {
			throw "Test 2 Failed: engine.currentCaller was null inside AST mode host FFI callback";
		}
		if (capturedCallerAST.methodName != "run") {
			throw 'Test 2 Failed: Unexpected AST caller method: ${capturedCallerAST.methodName}';
		}
		trace('SUCCESS: AST mode currentCaller identified: ${capturedCallerAST.className}.${capturedCallerAST.methodName} at line ${capturedCallerAST.line}');

		// Verify returning to host makes currentCaller null
		if (engine.currentCaller != null) {
			throw "Test 2b Failed: Expected currentCaller to reset to null after AST execution";
		}

		// Test 3: Bytecode VM Mode Script Call Context Identification
		var engineVM = new Haxiom();
		engineVM.useVM = true;

		var capturedCallerVM:ScriptStackFrame = null;
		engineVM.exposeValue("hostLogVM", function(msg:String) {
			capturedCallerVM = engineVM.currentCaller;
		});

		var scriptVM = '
            class TestScriptVM {
                public static function runVM() {
                    hostLogVM("Hello from VM");
                }
            }
        ';
		engineVM.interpret(scriptVM);
		engineVM.interpret("TestScriptVM.runVM();");

		if (capturedCallerVM == null) {
			throw "Test 3 Failed: engine.currentCaller was null inside VM mode host FFI callback";
		}
		if (capturedCallerVM.methodName != "runVM") {
			throw 'Test 3 Failed: Unexpected VM caller method: ${capturedCallerVM.methodName}';
		}
		trace('SUCCESS: VM mode currentCaller identified: ${capturedCallerVM.className}.${capturedCallerVM.methodName} at line ${capturedCallerVM.line}');

		// Verify returning to host makes currentCaller null
		if (engineVM.currentCaller != null) {
			throw "Test 3b Failed: Expected currentCaller to reset to null after VM execution";
		}

		trace("ALL CALLER IDENTIFICATION TESTS PASSED SUCCESSFULLY!");
	}
}
