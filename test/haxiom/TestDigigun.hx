package haxiom;

import haxiom.Haxiom;
import haxiom.FFI;

class TestDigigun {
    public static function main() {
        var haxiom = new Haxiom();
        haxiom.registerExposedClasses();
        
        // 1. 3rd Party Generic Library (digigun.core.types.Property)
        var propStr = new digigun.core.types.Property<String>("tamas"); // force compilation
        var propInt = new digigun.core.types.Property<Int>(42);         // force compilation
        var script1 = '
            var p1 = new digigun.core.types.Property<String>("sopronyi");
            var p2 = new digigun.core.types.Property<Int>(100);
            trace("3rd-party generic Property String: " + p1.value);
            trace("3rd-party generic Property Int: " + p2.value);
            p1.value = "sopronyi-changed";
            trace("3rd-party generic Property String changed: " + p1.value);
        ';
        haxiom.interpret(script1);

        // 2. 3rd Party Tuple and ETuple classes & enums (digigun.core.types.Tuple / ETuple)
        var forceTuple2 = new digigun.core.types.Tuple.Tuple2<String, Int>("", 0);
        var forceTuple3 = new digigun.core.types.Tuple.Tuple3<String, Int, Bool>("", 0, false);
        var forceETuple2 = digigun.core.types.Tuple.ETuple2.Values("", 0);
        var forceETuple3 = digigun.core.types.Tuple.ETuple3.Values("", 0, false);
        
        var script2 = '
            import digigun.core.types.Tuple;
            
            var t2 = new Tuple2<String, Int>("sopronyi", 999);
            var t3 = new Tuple3<String, Int, Bool>("tamas", 42, true);
            trace("Tuple2 values: " + t2.value1 + ", " + t2.value2);
            trace("Tuple3 values: " + t3.value1 + ", " + t3.value2 + ", " + t3.value3);

            var et2 = ETuple2.Values("hello", 777);
            var et3 = ETuple3.Values("world", 888, false);
            
            switch (et2) {
                case ETuple2.Values(v1, v2):
                    trace("ETuple2 matched: " + v1 + ", " + v2);
                default:
                    trace("ETuple2 match failed");
            }
            switch (et3) {
                case ETuple3.Values(v1, v2, v3):
                    trace("ETuple3 matched: " + v1 + ", " + v2 + ", " + v3);
                default:
                    trace("ETuple3 match failed");
            }
        ';
        haxiom.interpret(script2);
        
        // 3. Test matching qualified constructor names strictly on different enum types
        var script3 = '
            import digigun.core.types.Tuple;
            
            var et2 = ETuple2.Values("val1", 123);
            
            // Check that it does not match if the enum type qualifier is wrong
            var matchedWrong = false;
            switch (et2) {
                case ETuple3.Values(v1, v2, v3):
                    matchedWrong = true;
                default:
            }
            trace("Matched wrong: " + matchedWrong); // should be false
        ';
        haxiom.interpret(script3);
    }
}
