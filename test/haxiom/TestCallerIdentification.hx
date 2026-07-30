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

		// Test 4: Serialized bytecode preserves caller filename without source/currentFilename side channels.
		var compileEngine = new Haxiom();
		var bytecodeScript = '
            class BytecodeCaller {
                static public function main() {
                    hostLogBytecode("Hello from serialized bytecode");
                }
            }
        ';
		var bytecodeBytes = compileEngine.compileToBytecodeBytes(bytecodeScript, "BytecodeCaller.hx", null, true);

		var bytecodeEngine = new Haxiom();
		bytecodeEngine.useVM = true;
		var capturedBytecodeCaller:ScriptStackFrame = null;
		bytecodeEngine.exposeValue("hostLogBytecode", function(msg:String) {
			capturedBytecodeCaller = bytecodeEngine.currentCaller;
		});
		bytecodeEngine.executeBytecodeBytes(bytecodeBytes);

		if (capturedBytecodeCaller == null) {
			throw "Test 4 Failed: engine.currentCaller was null inside serialized bytecode host FFI callback";
		}
		if (capturedBytecodeCaller.file != "BytecodeCaller.hx") {
			throw 'Test 4 Failed: Expected serialized bytecode caller filename BytecodeCaller.hx but got ${capturedBytecodeCaller.file}';
		}
		if (capturedBytecodeCaller.methodName != "main") {
			throw 'Test 4 Failed: Unexpected serialized bytecode caller method: ${capturedBytecodeCaller.methodName}';
		}
		trace('SUCCESS: Serialized bytecode currentCaller preserved filename ${capturedBytecodeCaller.file}.');

		// Test 5: Release bytecode with stripped positions still reports the serialized script name.
		var releaseErrorScript = '
            class ReleaseBytecodeError {
                static public function main() {
                    throw "release-bytecode-crash";
                }
            }
        ';
		var releaseErrorBytes = compileEngine.compileToBytecodeBytes(releaseErrorScript, "ReleaseBytecodeError.hx", null, false);
		var caughtReleaseError = false;
		try {
			new Haxiom().executeBytecodeBytes(releaseErrorBytes);
		} catch (e:ScriptException) {
			caughtReleaseError = true;
			if (e.file != "ReleaseBytecodeError.hx") {
				throw 'Test 5 Failed: Expected release bytecode error filename ReleaseBytecodeError.hx but got ${e.file}';
			}
			if (e.formattedStackTrace.indexOf("ReleaseBytecodeError.hx") == -1) {
				throw 'Test 5 Failed: Release bytecode formatted stack trace missed serialized filename: ${e.formattedStackTrace}';
			}
		}
		if (!caughtReleaseError) {
			throw "Test 5 Failed: Expected release bytecode runtime error";
		}
		trace("SUCCESS: Release bytecode runtime errors preserve serialized filename.");

		trace("ALL CALLER IDENTIFICATION TESTS PASSED SUCCESSFULLY!");
	}
}
