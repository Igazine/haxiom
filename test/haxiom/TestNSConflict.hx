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

        trace("ALL SCOPE-AWARE TYPE AND DYNAMIC NAMESPACE VERIFICATIONS PASSED SUCCESSFULLY!");
    }
}
