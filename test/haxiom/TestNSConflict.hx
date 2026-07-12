package haxiom;

import haxiom.Haxiom;

class TestNSConflict {
    public static function main() {
        trace("Running Haxiom Scope-Aware Type Redefinition Verification...");

        // 1. Redefined type annotation check
        var engine1 = new Haxiom();
        engine1.useVM = true;
        var script1 = "
            class String {
                public var val:Dynamic;
                public function new(v:Dynamic) {
                    this.val = v;
                }
            }
            var customStr:String = new String('Hello Custom');
            customStr.val;
        ";
        var res1:Dynamic = engine1.interpret(script1);
        trace("Verification 1 (Shadowed Type Instantiation & Assignment): " + res1);
        if (res1 != "Hello Custom") {
            throw "Shadowed Type verification failed";
        }

        // 2. Fallback check when NOT redefined on a fresh instance
        var engine2 = new Haxiom();
        engine2.useVM = true;
        var script2 = "
            var regularStr:String = 'Hello Native';
            var num:Int = 42;
            regularStr + ' ' + num;
        ";
        var res2:Dynamic = engine2.interpret(script2);
        trace("Verification 2 (Native Fallback Typecheck): " + res2);
        if (res2 != "Hello Native 42") {
            throw "Native Fallback verification failed";
        }

        // 3. Shadowed Custom class package paths
        var engine3 = new Haxiom();
        engine3.useVM = true;
        var script3 = "
            package custom.pkg;
            class Helper {
                public var id:Int;
                public function new(i:Int) {
                    this.id = i;
                }
            }
            
            var h:custom.pkg.Helper = new custom.pkg.Helper(100);
            h.id;
        ";
        var res3:Dynamic = engine3.interpret(script3);
        trace("Verification 3 (Fully Qualified Package Path Typecheck): " + res3);
        if (res3 != 100) {
            throw "Package Path verification failed";
        }

        // 4. Dynamic Namespace Validation
        trace("Verification 4: Dynamic Namespace Validation");
        var validNS = ["plugin_a", "my.awesome.plugin", "_internal.v2"];
        var invalidNS = ["1plugin", ".plugin", "plugin..name", "plugin.1name", "plugin-a", ""];
        
        for (ns in validNS) {
            if (!Haxiom.isValidNamespace(ns)) {
                throw "Expected valid namespace but failed: " + ns;
            }
        }
        for (ns in invalidNS) {
            if (Haxiom.isValidNamespace(ns)) {
                throw "Expected invalid namespace but succeeded: " + ns;
            }
        }
        trace("Verification 4 (Dynamic Namespace Validation): PASSED");

        // 5. Host-Driven Sandboxed Namespace Loading (Single Haxiom instance)
        trace("Verification 5: Single Instance sandboxed modules");
        var engine = new Haxiom();
        engine.useVM = true;
        
        var scriptA = "
            class Main {
                public var msg:String;
                public function new() {
                    msg = 'Hello from Mod A';
                }
                public function getMsg():String {
                    return msg;
                }
            }
        ";
        
        var scriptB = "
            class Main {
                public var msg:String;
                public function new() {
                    msg = 'Hello from Mod B';
                }
                public function getMsg():String {
                    return msg;
                }
            }
        ";

        // Load both into different namespaces
        engine.interpret(scriptA, null, false, "mod_a");
        engine.interpret(scriptB, null, false, "mod_b");

        // Instantiate both dynamically at runtime
        var instA:Dynamic = engine.interpret("new mod_a.Main();");
        var instB:Dynamic = engine.interpret("new mod_b.Main();");

        var msgA:String = engine.resolveField(instA, "getMsg")();
        var msgB:String = engine.resolveField(instB, "getMsg")();
        
        trace("Verification 5 (Mod A Message): " + msgA);
        trace("Verification 5 (Mod B Message): " + msgB);

        if (msgA != "Hello from Mod A" || msgB != "Hello from Mod B") {
            throw "Host-Driven Sandboxed Namespace execution failed: class definitions collided or returned wrong values";
        }
        trace("Verification 5 (Single Instance sandboxed modules): PASSED");

        // Verification 6: Error Callbacks and Namespace Halting
        trace("Verification 6: Testing Error Callbacks and Namespace Halting...");
        
        var compileErrorCaught = false;
        var runtimeErrorCaught = false;
        var lastCompileError:haxiom.ScriptException = null;
        var lastRuntimeError:haxiom.ScriptException = null;
        
        var errorEngine = new haxiom.Haxiom();
        
        errorEngine.onCompilerError = function(e) {
            compileErrorCaught = true;
            lastCompileError = e;
        };
        
        errorEngine.onRuntimeError = function(e) {
            runtimeErrorCaught = true;
            lastRuntimeError = e;
        };
        
        // 1. Verify Compiler Error Callback
        var invalidScript = "class Bad { static function main() { return 1 + ; } }";
        var res = errorEngine.compile(invalidScript);
        if (res != null || !compileErrorCaught) {
            throw "Verification 6 failed: compiler error callback not triggered or did not suppress exception";
        }
        trace("Verification 6 (Compiler Error Callback): PASSED");
        
        // 2. Verify Runtime Error Namespace Halting (VM Mode)
        errorEngine.useVM = true;
        var runtimeErrScript = "
            class BuggyMod {
                static public function doCrash() {
                    var x:Dynamic = null;
                    return x.someField; // Null pointer exception
                }
                static public function doSuccess() {
                    return 'Mod execution success!';
                }
            }
        ";
        
        errorEngine.interpret(runtimeErrScript, null, false, "buggy_ns");
        
        runtimeErrorCaught = false;
        var crashRes = errorEngine.interpret("buggy_ns.BuggyMod.doCrash();");
        if (crashRes != null || !runtimeErrorCaught) {
            throw "Verification 6 failed: VM runtime error callback not triggered or did not suppress exception";
        }
        
        if (!errorEngine.isNamespaceHalted("buggy_ns")) {
            throw "Verification 6 failed: buggy_ns namespace not halted after VM runtime exception";
        }
        trace("Verification 6 (VM Namespace Halting on Exception): PASSED");
        
        // Try to call doSuccess() in halted namespace in VM mode
        var successRes = errorEngine.interpret("buggy_ns.BuggyMod.doSuccess();");
        if (successRes != null) {
            throw "Verification 6 failed: method in halted namespace buggy_ns was executed under VM mode";
        }
        trace("Verification 6 (VM Halted Namespace Block): PASSED");

        // 3. Verify Runtime Error Namespace Halting (AST Mode)
        errorEngine.clearHaltedNamespaces();
        if (errorEngine.isNamespaceHalted("buggy_ns")) {
            throw "Verification 6 failed: clearHaltedNamespaces did not clear buggy_ns halt status";
        }
        errorEngine.useVM = false;
        
        runtimeErrorCaught = false;
        var crashResAST = errorEngine.interpret("buggy_ns.BuggyMod.doCrash();");
        if (crashResAST != null || !runtimeErrorCaught) {
            throw "Verification 6 failed: AST runtime error callback not triggered or did not suppress exception";
        }
        
        if (!errorEngine.isNamespaceHalted("buggy_ns")) {
            throw "Verification 6 failed: buggy_ns namespace not halted after AST runtime exception";
        }
        trace("Verification 6 (AST Namespace Halting on Exception): PASSED");
        
        // Try to call doSuccess() in halted namespace in AST mode
        var successResAST = errorEngine.interpret("buggy_ns.BuggyMod.doSuccess();");
        if (successResAST != null) {
            throw "Verification 6 failed: method in halted namespace buggy_ns was executed under AST mode";
        }
        trace("Verification 6 (AST Halted Namespace Block): PASSED");

        trace("ALL SCOPE-AWARE TYPE, DYNAMIC NAMESPACE AND ERROR HANDLING CALLBACK VERIFICATIONS PASSED SUCCESSFULLY!");
    }
}
