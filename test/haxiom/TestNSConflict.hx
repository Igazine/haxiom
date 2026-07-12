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

        trace("ALL SCOPE-AWARE TYPE VERIFICATIONS PASSED SUCCESSFULLY!");
    }
}
