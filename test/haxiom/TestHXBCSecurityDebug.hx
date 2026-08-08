package haxiom;

import haxiom.Haxiom;
import haxiom.HXBCKey;
import haxiom.ScriptException;
import haxe.io.Bytes;

class TestHXBCSecurityDebug {
    public static function runTests() {
        trace("Starting HXBC Security and Debug Symbols Verification Suite...");
        
        testBytecodeEncryption();
        testBytecodeObfuscationCheck();
        testDebugSymbolsAndLocalsDump();
        testEngineExposureBlockage();
        testAutoExecuteMain();
        testNativeClassCasting();
        testClassRedefinitionBlockage();
        testMainClassRouting();
        testScriptContextSourceLabelFallback();
		testVMMethodSpecificAccessMetadata();
        
        trace("SUCCESS: All HXBC Security and Debug Symbols tests passed!");
    }

	static function testVMMethodSpecificAccessMetadata():Void {
		var source = '
			class AccessTarget {
				public function new() {}
				function hidden():Int return 42;
			}
			class AccessCaller {
				public function new() {}
				@:access(AccessTarget.hidden)
				public function read(target:AccessTarget):Int return target.hidden();
			}
			class VMAccessMetadata {
				static public function main():Int {
					return new AccessCaller().read(new AccessTarget());
				}
			}
		';
		var result:Int = new Haxiom().interpret(source, new ScriptContext("VMAccessMetadata"));
		if (result != 42)
			throw 'VM method-specific @:access returned $result';
		trace("SUCCESS: VM method-specific @:access verified.");
	}

    static function testBytecodeEncryption() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = "
            var a = 10;
            var b = 20;
            a + b;
        ";

        var key:HXBCKey = "my_secret_encryption_salt_123";

        // Compile with key
        var bytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), key);
        if (bytes == null) throw "Failed to compile bytecode with key";

        // 1. Run with correct key
        var engine2 = new Haxiom();
        engine2.useVM = true;
        var res:Int = engine2.executeBytecodeBytes(bytes, script, key);
        if (res != 30) throw "Encryption execution failed: expected 30, got " + res;

        // 2. Run with wrong key - should fail checksum/verification
        var wrongKey:HXBCKey = "wrong_salt";
        var caughtWrongKey = false;
        try {
            engine2.executeBytecodeBytes(bytes, script, wrongKey);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("Invalid encryption key") != -1) {
                caughtWrongKey = true;
            }
        }
        if (!caughtWrongKey) throw "Expected error for wrong encryption key";

        // 3. Run with no key - should throw specific error
        var caughtNoKey = false;
        try {
            engine2.executeBytecodeBytes(bytes, script, null);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("requires a key to load") != -1) {
                caughtNoKey = true;
            }
        }
        if (!caughtNoKey) throw "Expected error for missing encryption key";

        // 4. Compile without key, try to run with key
        var plainBytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), null);
        var caughtKeyOnPlain = false;
        try {
            engine2.executeBytecodeBytes(plainBytes, script, key);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("is not encrypted but a key was provided") != -1) {
                caughtKeyOnPlain = true;
            }
        }
        if (!caughtKeyOnPlain) throw "Expected error when passing key to plain bytecode";

        trace("SUCCESS: Bytecode Encryption verified.");
    }

    static function bytesToHex(bytes:Bytes):String {
        var s = new StringBuf();
        for (i in 0...bytes.length) {
            s.add(StringTools.hex(bytes.get(i), 2));
        }
        return s.toString().toLowerCase();
    }

    static function testBytecodeObfuscationCheck() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = "
            var mySecretVariableName = 999;
            mySecretVariableName;
        ";

        var targetStr = "mySecretVariableName";
        var targetHex = bytesToHex(Bytes.ofString(targetStr));

        // 1. Compile plain bytecode (no key)
        var plainBytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), null);
        var plainHex = bytesToHex(plainBytes);
        // Since it's plain serialization, the string constants (including the variable name) should be visible in the hex representation
        if (plainHex.indexOf(targetHex) == -1) {
            throw "Plain bytecode constant pool strings not found";
        }

        // 2. Compile encrypted bytecode (with key)
        var key:HXBCKey = "obfuscation_key";
        var encBytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), key);
        var encHex = bytesToHex(encBytes);
        // The strings should be completely scrambled and invisible
        if (encHex.indexOf(targetHex) != -1) {
            throw "Encrypted bytecode leaked constant pool string";
        }

        trace("SUCCESS: Bytecode Obfuscation verified.");
    }

    static function testDebugSymbolsAndLocalsDump() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = "
            function main() {
                var localX = 100;
                var localY = 'hello';
                // Trigger a crash
                throw 'crash-test';
            }
            main();
        ";

        // 1. Compile without debug symbols, check no local state is dumped
        var releaseBytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), null, false);
        var caughtRelease = false;
        try {
            engine.executeBytecodeBytes(releaseBytes, script);
        } catch (e:ScriptException) {
            caughtRelease = true;
            if (e.locals != null) {
                trace("DEBUG e.locals keys: " + [for (k in e.locals.keys()) k] + " map: " + e.locals);
                throw "Release build should not have debug symbols / locals";
            }
            if (e.message.indexOf("Local Variables:") != -1) throw "Release build stack trace should not contain locals dump";
        }
        if (!caughtRelease) throw "Expected exception to be thrown by release bytecode";

        // 2. Compile with debug symbols, check local state is present and formatted
        var debugBytes = engine.compileToBytecodeBytes(script, new ScriptContext(null, "test_file"), null, true);
        var caughtDebug = false;
        try {
            engine.executeBytecodeBytes(debugBytes, script);
        } catch (e:ScriptException) {
            caughtDebug = true;
            if (e.locals == null) throw "Debug build did not capture locals";
            if (e.locals.get("localX") != 100) throw "Incorrect captured localX: " + e.locals.get("localX");
            if (e.locals.get("localY") != "hello") throw "Incorrect captured localY: " + e.locals.get("localY");
            if (e.message.indexOf("Local Variables:") == -1) throw "Debug stack trace missing Local Variables section";
            if (e.message.indexOf("- localX: 100") == -1) throw "Debug stack trace missing localX value";
            if (e.message.indexOf("- localY: hello") == -1) throw "Debug stack trace missing localY value";
        }
        if (!caughtDebug) throw "Expected exception to be thrown by debug bytecode";

        trace("SUCCESS: Debug Symbols and Locals Dump verified.");
    }

    static function testEngineExposureBlockage() {
        var engine = new Haxiom();
        engine.importWhitelist = null; // Open up the whitelist to test override

        var script = "
            import haxiom.Haxiom;
            var h = new Haxiom();
        ";
        var caught = false;
        try {
            engine.interpret(script);
        } catch (e:Dynamic) {
            caught = true;
        }
        if (!caught) {
            throw "Engine exposure blockage failed: guest script was able to load haxiom.Haxiom!";
        }

        var script2 = "
            import haxiom.Interp;
            var i = new Interp();
        ";
        var caught2 = false;
        try {
            engine.interpret(script2);
        } catch (e:Dynamic) {
            caught2 = true;
        }
        if (!caught2) {
            throw "Engine exposure blockage failed: guest script was able to load haxiom.Interp!";
        }

        trace("SUCCESS: Engine exposure blockage verified.");
    }

    static function testAutoExecuteMain() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = "
            class AutoMainDemo {
                static public var ran:Bool = false;
                static public function main() {
                    ran = true;
                }
            }
        ";

        engine.interpret(script, new ScriptContext("AutoMainDemo"));

        var clsVal = engine.getGlobal("AutoMainDemo");
        var ranVal = engine.resolveField(clsVal, "ran");
        if (ranVal != true) {
            throw "Automatic main execution failed: AutoMainDemo.main was not run!";
        }

        // Test AST mode as well
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        engineAST.interpret(script, new ScriptContext("AutoMainDemo"));

        var clsValAST = engineAST.getGlobal("AutoMainDemo");
        var ranValAST = engineAST.resolveField(clsValAST, "ran");
        if (ranValAST != true) {
            throw "Automatic main execution (AST) failed: AutoMainDemo.main was not run!";
        }

        var invalidMainScript = "
            class PrivateMainDemo {
                static public var ran:Bool = false;
                static private function main() {
                    ran = true;
                }
            }

            class ArgumentMainDemo {
                static public var ran:Bool = false;
                static public function main(required:Int) {
                    ran = true;
                }
            }
        ";

        for (useVM in [false, true]) {
            var invalidEngine = new Haxiom();
            invalidEngine.enableDCE = false;
            invalidEngine.useVM = useVM;
            invalidEngine.interpret(invalidMainScript);

            var privateClass = invalidEngine.getGlobal("PrivateMainDemo");
            var argumentClass = invalidEngine.getGlobal("ArgumentMainDemo");
            if (invalidEngine.resolveField(privateClass, "ran") != false) {
                throw "Private static main was executed automatically";
            }
            if (invalidEngine.resolveField(argumentClass, "ran") != false) {
                throw "Argument-requiring static main was executed automatically";
            }
        }

        trace("SUCCESS: Automatic main execution verified.");
    }

    static function testNativeClassCasting() {
        var engine = new Haxiom();
        engine.useVM = true;
        
        engine.registerClass("haxe.crypto.Sha1", haxe.crypto.Sha1);

        var script = "
            import haxe.crypto.Sha1;
            class CastDemo {
                static public function main() {
                    var rawObj:Dynamic = new Sha1();
                    var casted = cast(rawObj, Sha1);
                }
            }
        ";
        
        engine.interpret(script);
        
        // Test AST mode as well
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        engineAST.registerClass("haxe.crypto.Sha1", haxe.crypto.Sha1);
        engineAST.interpret(script);

        trace("SUCCESS: Native class casting verified.");
    }

    static function testClassRedefinitionBlockage() {
        var engine = new Haxiom();
        var script = "
            class RedefDemo {
                static public function main() {}
            }
            class OtherCls {}
            class RedefDemo {
                static public function main() {}
            }
        ";
        var caught = false;
        try {
            engine.compile(script);
        } catch (e:ScriptException) {
            if (StringTools.contains(e.message, "Redefinition of class RedefDemo")) {
                caught = true;
            } else {
                throw "Unexpected redefinition compiler error: " + e.message;
            }
        } catch (e:Dynamic) {
            throw "Unexpected exception type on redefinition: " + e;
        }
        if (!caught) {
            throw "Class redefinition was not blocked!";
        }
        trace("SUCCESS: Class redefinition blockage verified.");
    }

    static function testMainClassRouting() {
        var script = "
            class AnotherClass {
                static public var ran:Bool = false;
                static public function main() {
                    ran = true;
                }
            }
            class Basic {
                static public var ran:Bool = false;
                static public function main() {
                    ran = true;
                }
            }
        ";

        // Test 1: Prioritize Basic based on filename matching "Basic.hx"
        var engine1 = new Haxiom();
        engine1.useVM = true;
        engine1.interpret(script, new ScriptContext("Basic", "Basic.hx"));
        
        var clsAnother1 = engine1.getGlobal("AnotherClass");
        var clsBasic1 = engine1.getGlobal("Basic");
        if (engine1.resolveField(clsAnother1, "ran") == true) {
            throw "Incorrectly executed AnotherClass.main instead of Basic.main when filename was Basic.hx";
        }
        if (engine1.resolveField(clsBasic1, "ran") != true) {
            throw "Failed to execute Basic.main when filename was Basic.hx";
        }

        // Test 2: Prioritize AnotherClass based on override flag
        var engine2 = new Haxiom();
        engine2.useVM = true;
        engine2.interpret(script, new ScriptContext("AnotherClass", "Basic.hx"));

        var clsAnother2 = engine2.getGlobal("AnotherClass");
        var clsBasic2 = engine2.getGlobal("Basic");
        if (engine2.resolveField(clsAnother2, "ran") != true) {
            throw "Failed to execute AnotherClass.main under explicit override";
        }
        if (engine2.resolveField(clsBasic2, "ran") == true) {
            throw "Incorrectly executed Basic.main under override AnotherClass";
        }

        // Test 3: A source string without a script name has no implicit entry point
        for (useVM in [false, true]) {
            var unnamedEngine = new Haxiom();
            unnamedEngine.enableDCE = false;
            unnamedEngine.useVM = useVM;
            unnamedEngine.interpret(script);
            assertMainRouting(unnamedEngine, false, false, 'unnamed ${useVM ? "VM" : "AST"} source');
        }

        // Test 4: Entry-point selection survives both serialized representations
        var astCompiler = new Haxiom();
        astCompiler.useVM = false;
        var astBytes = astCompiler.compileToASTBytes(script, new ScriptContext("Basic", "Basic.hx"));
        var astRuntime = new Haxiom();
        astRuntime.useVM = false;
        astRuntime.executeASTBytes(astBytes);
        assertMainRouting(astRuntime, true, false, "AST bytes");

        for (compress in [false, true]) {
            var bytecodeCompiler = new Haxiom();
            bytecodeCompiler.useVM = true;
            var bytecodeBytes = bytecodeCompiler.compileToBytecodeBytes(script, new ScriptContext("Basic", "Basic.hx"), null, false, compress);
            var bytecodeRuntime = new Haxiom();
            bytecodeRuntime.useVM = true;
            bytecodeRuntime.executeBytecodeBytes(bytecodeBytes);
            assertMainRouting(bytecodeRuntime, true, false, compress ? "compressed HXBC" : "raw HXBC");
        }

        trace("SUCCESS: Main class routing verified.");
    }

    static function assertMainRouting(engine:Haxiom, basicRan:Bool, anotherRan:Bool, context:String) {
        var basicClass = engine.getGlobal("Basic");
        var anotherClass = engine.getGlobal("AnotherClass");
        if (engine.resolveField(basicClass, "ran") != basicRan) {
            throw 'Basic.main routing mismatch for $context';
        }
        if (engine.resolveField(anotherClass, "ran") != anotherRan) {
            throw 'AnotherClass.main routing mismatch for $context';
        }
    }

    static function testScriptContextSourceLabelFallback() {
        var script = '
            class ContextNameOnly {
                static public function main() {
                    throw "context-label-fallback";
                }
            }
        ';
        var context = new ScriptContext("ContextNameOnly");

        for (useVM in [false, true]) {
            var engine = new Haxiom();
            engine.useVM = useVM;
            assertContextLabel(() -> engine.interpret(script, context), useVM ? "VM interpret" : "AST interpret");
        }

        var astCompiler = new Haxiom();
        astCompiler.useVM = false;
        var astBytes = astCompiler.compileToASTBytes(script, context);
        var astRuntime = new Haxiom();
        astRuntime.useVM = false;
        assertContextLabel(() -> astRuntime.executeASTBytes(astBytes, script), "AST bytes");

        for (compress in [false, true]) {
            var bytecode = new Haxiom().compileToBytecodeBytes(script, context, null, false, compress);
            assertContextLabel(() -> new Haxiom().executeBytecodeBytes(bytecode, script),
                compress ? "compressed HXBC" : "raw HXBC");
        }

        trace("SUCCESS: ScriptContext source-label fallback verified.");
    }

    static function assertContextLabel(run:Void->Void, path:String) {
        try {
            run();
        } catch (e:ScriptException) {
            if (e.file != "ContextNameOnly") {
                throw 'ScriptContext name fallback failed via $path: ${e.file}';
            }
            if (e.formattedStackTrace.indexOf("ContextNameOnly") == -1) {
                throw 'ScriptContext name fallback missing from stack trace via $path';
            }
            return;
        }
        throw 'Expected ScriptContext fallback error via $path';
    }
}
