package haxiom;

import haxiom.Haxiom;
import haxiom.VM;

class TestInlineCache {
    public static function main() {
        trace("Starting Haxiom VM Inline Caching Verification...");
        
        var engine = new Haxiom();
        engine.useVM = true;
        
        // 1. Guest Class Method Caching Test
        var script = "
            class Dog {
                public var name:String;
                public function new(n:String) {
                    name = n;
                }
                public function greet(prefix:String):String {
                    return prefix + ' ' + name;
                }
            }
            
            var d1 = new Dog('Buddy');
            var d2 = new Dog('Rocky');
            
            // Loop calling method on the SAME instance (tests Monomorphic Instance Cache hit)
            var res1 = '';
            var i = 0;
            while (i < 3) {
                res1 += d1.greet('Hello') + ',';
                i++;
            }
            
            // Loop calling method on DIFFERENT instances of the SAME class (tests Monomorphic Class Cache hit)
            var res2 = d1.greet('Hi') + '|' + d2.greet('Hi');
            
            res1 + ' / ' + res2;
        ";
        
        var result:String = engine.interpret(script);
        trace("Guest Class cache result: " + result);
        if (result != "Hello Buddy,Hello Buddy,Hello Buddy, / Hi Buddy|Hi Rocky") {
            throw "Guest Class caching failed: expected 'Hello Buddy,Hello Buddy,Hello Buddy, / Hi Buddy|Hi Rocky', got: " + result;
        }
        
        // 2. FFI Host Object Method Caching Test
        var hostObject:Dynamic = null;
        hostObject = {
            count: 0,
            increment: function(amount:Int):Int {
                return hostObject.count += amount;
            }
        };
        
        engine.setGlobal("host", hostObject);
        var ffiScript = "
            var i = 0;
            while (i < 5) {
                host.increment(2);
                i++;
            }
            host.count;
        ";
        
        var ffiResult:Int = engine.interpret(ffiScript);
        trace("FFI Host Object cache result: " + ffiResult);
        if (ffiResult != 10) {
            throw "FFI Host Object caching failed: expected 10, got " + ffiResult;
        }
        
        trace("ALL INLINE CACHE VERIFICATIONS PASSED SUCCESSFULLY!");
    }
}
