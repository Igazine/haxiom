package haxiom;

import haxiom.Haxiom;

class TestSafeguardsTCO {
    public static function runTests() {
        trace("Starting Safeguards & TCO Verification Suite...");
        
        testTailCallOptimization();
        testHeapSafeguards();
        testPolymorphicInlineCache();
        
        trace("SUCCESS: All Safeguards and TCO tests passed!");
    }

    static function testTailCallOptimization() {
        trace("  Testing Tail-Call Optimization (TCO)...");
        var engine = new Haxiom();
        engine.useVM = true;

        // 1. Direct function recursive call
        var directScript = "
            function countDirect(n, acc) {
                if (n <= 0) return acc;
                return countDirect(n - 1, acc + 1);
            }
            countDirect(10000, 0);
        ";
        var directResult = engine.interpret(directScript);
        if (directResult != 10000) {
            throw "TCO direct recursive call failed: expected 10000, got " + directResult;
        }

        // 2. Class method recursive call (using this.f)
        var classScript = "
            class RecurseTest {
                public function new() {}
                public function countMethod(n, acc) {
                    if (n <= 0) return acc;
                    return this.countMethod(n - 1, acc + 1);
                }
            }
            var r = new RecurseTest();
            r.countMethod(10000, 0);
        ";
        var classResult = engine.interpret(classScript);
        if (classResult != 10000) {
            throw "TCO class method recursive call failed: expected 10000, got " + classResult;
        }

        // 3. Recursive call with fewer arguments (ensures defaults/null mapping work and old parameter value is not retained)
        var missingArgsScript = "
            function countFewer(n, acc) {
                if (n <= 0) {
                    return acc == null ? 999 : acc;
                }
                // Call with fewer args (second arg 'acc' is missing)
                return countFewer(n - 1);
            }
            countFewer(5000);
        ";
        var fewerResult = engine.interpret(missingArgsScript);
        if (fewerResult != 999) {
            throw "TCO fewer arguments recursive call failed: expected 999, got " + fewerResult;
        }

        trace("    SUCCESS: TCO verified.");
    }

    static function testHeapSafeguards() {
        trace("  Testing Heap Safeguards (Memory Watchdog)...");
        
        // 1. Array growth watchdog check
        var engine1 = new Haxiom();
        engine1.useVM = true;
        engine1.maxMemory = 100;
        
        var arrayScript = "
            var arr = [];
            var i = 0;
            while (i < 150) {
                arr.push(i);
                i++;
            }
            arr.length;
        ";
        var threwArray = false;
        try {
            engine1.interpret(arrayScript);
        } catch (e:haxiom.ScriptException) {
            if (e.message.indexOf("Memory limit exceeded") != -1) {
                threwArray = true;
            } else {
                throw "Heap Safeguards Array: unexpected ScriptException message: " + e.message;
            }
        } catch (e:Dynamic) {
            throw "Heap Safeguards Array: unexpected exception type: " + Std.string(e);
        }
        if (!threwArray) {
            throw "Heap Safeguards Array: did not throw when memory limit was exceeded";
        }

        // 2. Map set watchdog check
        var engine2 = new Haxiom();
        engine2.useVM = true;
        engine2.maxMemory = 50;

        var mapScript = "
            var m = new Map();
            var i = 0;
            while (i < 100) {
                m.set('k_' + i, i);
                i++;
            }
            m.length;
        ";
        var threwMap = false;
        try {
            engine2.interpret(mapScript);
        } catch (e:haxiom.ScriptException) {
            if (e.message.indexOf("Memory limit exceeded") != -1) {
                threwMap = true;
            } else {
                throw "Heap Safeguards Map: unexpected ScriptException message: " + e.message;
            }
        } catch (e:Dynamic) {
            throw "Heap Safeguards Map: unexpected exception type: " + Std.string(e);
        }
        if (!threwMap) {
            throw "Heap Safeguards Map: did not throw when memory limit was exceeded";
        }

        // 3. Object field assignment watchdog check
        var engine3 = new Haxiom();
        engine3.useVM = true;
        engine3.maxMemory = 30;
        engine3.importWhitelist.push("Reflect");

        var objectScript = "
            import Reflect;
            var obj = {};
            var i = 0;
            while (i < 50) {
                Reflect.setField(obj, 'f_' + i, i);
                i++;
            }
        ";
        var threwObj = false;
        try {
            engine3.interpret(objectScript);
        } catch (e:haxiom.ScriptException) {
            if (e.message.indexOf("Memory limit exceeded") != -1) {
                threwObj = true;
            } else {
                throw "Heap Safeguards Object: unexpected ScriptException message: " + e.message;
            }
        } catch (e:Dynamic) {
            throw "Heap Safeguards Object: unexpected exception type: " + Std.string(e);
        }
        if (!threwObj) {
            throw "Heap Safeguards Object: did not throw when memory limit was exceeded";
        }

        trace("    SUCCESS: Heap Safeguards verified.");
    }

    static function testPolymorphicInlineCache() {
        trace("  Testing Polymorphic Inline Caching (IC)...");
        var engine = new Haxiom();
        engine.useVM = true;

        var script = "
            class CA {
                public var val:Int = 10;
                public function new() {}
                public function getVal() { return val; }
            }
            class CB {
                public var val:Int = 20;
                public function new() {}
                public function getVal() { return val; }
            }
            class CC {
                public var val:Int = 30;
                public function new() {}
                public function getVal() { return val; }
            }
            class CD {
                public var val:Int = 40;
                public function new() {}
                public function getVal() { return val; }
            }
            class CE {
                public var val:Int = 50;
                public function new() {}
                public function getVal() { return val; }
            }

            var instances = [new CA(), new CB(), new CC(), new CD(), new CE()];

            // 1. Call on 3 alternating classes (should trigger Polymorphic inline cache hits)
            var sumPoly = 0;
            var i = 0;
            while (i < 300) {
                var inst = instances[i % 3];
                sumPoly += inst.getVal();
                i++;
            }

            // 2. Call on 5 alternating classes (should exceed cap 4 and fallback to megamorphic)
            var sumMega = 0;
            var j = 0;
            while (j < 500) {
                var inst = instances[j % 5];
                sumMega += inst.getVal();
                j++;
            }

            [sumPoly, sumMega];
        ";

        var results:Array<Int> = engine.interpret(script);
        if (results[0] != 6000) { // average: (10+20+30)/3 = 20 * 300 = 6000
            throw "Polymorphic IC failed: expected 6000, got " + results[0];
        }
        if (results[1] != 15000) { // average: (10+20+30+40+50)/5 = 30 * 500 = 15000
            throw "Megamorphic IC fallback failed: expected 15000, got " + results[1];
        }

        trace("    SUCCESS: Polymorphic IC verified.");
    }
}
