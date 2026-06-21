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
        
        trace("SUCCESS: All HXBC Security and Debug Symbols tests passed!");
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
        var bytes = engine.compileToBytecodeBytes(script, "test_file", key);
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
        var plainBytes = engine.compileToBytecodeBytes(script, "test_file", null);
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
        var plainBytes = engine.compileToBytecodeBytes(script, "test_file", null);
        var plainHex = bytesToHex(plainBytes);
        // Since it's plain serialization, the string constants (including the variable name) should be visible in the hex representation
        if (plainHex.indexOf(targetHex) == -1) {
            throw "Plain bytecode constant pool strings not found";
        }

        // 2. Compile encrypted bytecode (with key)
        var key:HXBCKey = "obfuscation_key";
        var encBytes = engine.compileToBytecodeBytes(script, "test_file", key);
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
        var releaseBytes = engine.compileToBytecodeBytes(script, "test_file", null, false);
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
        var debugBytes = engine.compileToBytecodeBytes(script, "test_file", null, true);
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

        engine.interpret(script);

        var clsVal:haxiom.Interp.HaxiomClass = cast engine.interp.globals.get("AutoMainDemo");
        var ranVal = clsVal.staticFields.get("ran");
        if (ranVal != true) {
            throw "Automatic main execution failed: AutoMainDemo.main was not run!";
        }

        // Test AST mode as well
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        engineAST.interpret(script);

        var clsValAST:haxiom.Interp.HaxiomClass = cast engineAST.interp.globals.get("AutoMainDemo");
        var ranValAST = clsValAST.staticFields.get("ran");
        if (ranValAST != true) {
            throw "Automatic main execution (AST) failed: AutoMainDemo.main was not run!";
        }

        trace("SUCCESS: Automatic main execution verified.");
    }

    static function testNativeClassCasting() {
        var engine = new Haxiom();
        engine.useVM = true;
        
        FFI.registerClass(engine, "haxe.crypto.Sha1", haxe.crypto.Sha1);

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
        FFI.registerClass(engineAST, "haxe.crypto.Sha1", haxe.crypto.Sha1);
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
        engine1.currentFilename = "Basic.hx";
        engine1.interpret(script);
        
        var clsAnother1:haxiom.Interp.HaxiomClass = cast engine1.interp.globals.get("AnotherClass");
        var clsBasic1:haxiom.Interp.HaxiomClass = cast engine1.interp.globals.get("Basic");
        if (clsAnother1.staticFields.get("ran") == true) {
            throw "Incorrectly executed AnotherClass.main instead of Basic.main when filename was Basic.hx";
        }
        if (clsBasic1.staticFields.get("ran") != true) {
            throw "Failed to execute Basic.main when filename was Basic.hx";
        }

        // Test 2: Prioritize AnotherClass based on override flag
        var engine2 = new Haxiom();
        engine2.useVM = true;
        engine2.mainClassOverride = "AnotherClass";
        engine2.currentFilename = "Basic.hx";
        engine2.interpret(script);

        var clsAnother2:haxiom.Interp.HaxiomClass = cast engine2.interp.globals.get("AnotherClass");
        var clsBasic2:haxiom.Interp.HaxiomClass = cast engine2.interp.globals.get("Basic");
        if (clsAnother2.staticFields.get("ran") != true) {
            throw "Failed to execute AnotherClass.main under explicit override";
        }
        if (clsBasic2.staticFields.get("ran") == true) {
            throw "Incorrectly executed Basic.main under override AnotherClass";
        }

        trace("SUCCESS: Main class routing verified.");
    }
}
