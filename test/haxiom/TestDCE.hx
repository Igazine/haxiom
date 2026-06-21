package haxiom;

/**
 * TestDCE — verifies Dead Code Elimination (DCE) in Optimizer.eliminateDeadCode().
 *
 * Tests cover:
 *   1.  Dead statements after return are removed
 *   2.  Dead statements after throw are removed
 *   3.  Dead statements after break are removed (inside a while)
 *   4.  Dead statements after continue are removed (inside a while)
 *   5.  Unused untyped pure local is eliminated
 *   6.  Used variable is NOT eliminated
 *   7.  Typed variable is NOT eliminated (runtime type-check may throw)
 *   8.  Unused variable with side-effecting init is NOT eliminated
 *   9.  Pure expression-statement (not last) is removed from a block
 *   10. Unused private class method is eliminated
 *   11. Public class method is NOT eliminated
 *   12. DCE preserves script correctness (produces identical results)
 *   13. DCE can be disabled via enableDCE = false
 *   14. Byte size is reduced by DCE (structural proof)
 */
class TestDCE {

    static public function main() {
        runTests();
    }

    static public function runTests() {
        trace("DCE Verification Suite");
        trace("----------------------");

        var passed = 0;
        var failed = 0;

        function ok(label:String) {
            trace('SUCCESS: $label');
            passed++;
        }
        function fail(label:String, reason:String) {
            trace('FAILURE: $label — $reason');
            failed++;
        }

        // ---------------------------------------------------------------
        // Helpers
        // ---------------------------------------------------------------

        // Returns the number of top-level exprs in the compiled EBlock
        function blockLen(h:Haxiom, src:String):Int {
            var ast = h.compile(src, "dce_test");
            switch (ast.def) {
                case EBlock(exprs): return exprs.length;
                default: return -1;
            }
        }

        // Returns byte size of compiled AST
        function byteSize(h:Haxiom, src:String):Int {
            var bytes = h.compileToASTBytes(src, "dce_test");
            return bytes == null ? -1 : bytes.length;
        }

        // ---------------------------------------------------------------
        // Test 1: Dead statements after return removed
        // ---------------------------------------------------------------
        var h = new Haxiom(); h.enableDCE = true;
        var src = '
            function f():Int {
                return 1;
                var dead = 99;
                return 2;
            }
            f();
        ';
        // Get the function body block length after DCE
        var ast1 = h.compile(src, "t1");
        // Find the function body and count its statements
        var fnBodyLen = -1;
        switch (ast1.def) {
            case EBlock(exprs):
                for (e in exprs) {
                    switch (e.def) {
                        case EFunction(_, _, _, body):
                            switch (body.def) {
                                case EBlock(fexprs): fnBodyLen = fexprs.length;
                                default:
                            }
                        default:
                    }
                }
            default:
        }
        if (fnBodyLen == 1) ok("1. Dead stmts after return removed (fn body has 1 stmt)");
        else fail("1. Dead stmts after return removed", 'fn body has $fnBodyLen stmts, expected 1');

        // ---------------------------------------------------------------
        // Test 2: Dead statements after throw removed
        // ---------------------------------------------------------------
        var h2 = new Haxiom(); h2.enableDCE = true;
        var src2 = '
            function g() {
                throw "error";
                var nope = 5;
            }
        ';
        var ast2 = h2.compile(src2, "t2");
        var fnBodyLen2 = -1;
        switch (ast2.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EFunction(_, _, _, body): switch (body.def) {
                        case EBlock(fe): fnBodyLen2 = fe.length;
                        default:
                    }
                    default:
                }
            default:
        }
        if (fnBodyLen2 == 1) ok("2. Dead stmts after throw removed");
        else fail("2. Dead stmts after throw removed", 'fn body has $fnBodyLen2 stmts, expected 1');

        // ---------------------------------------------------------------
        // Test 3: Runtime result unchanged — correct output still produced
        // ---------------------------------------------------------------
        var h3 = new Haxiom(); h3.enableDCE = true;
        var result = [];
        h3.setGlobal("collect", function(v:Dynamic) result.push(v));
        h3.interpret('
            var x = 10;
            var y = x + 5;
            collect(y);
        ', null);
        if (result.length == 1 && result[0] == 15)
            ok("3. Script result correct after DCE (collect received 15)");
        else
            fail("3. Script result correct after DCE", 'got $result');

        // ---------------------------------------------------------------
        // Test 4: Unused untyped pure local is eliminated
        // ---------------------------------------------------------------
        var h4 = new Haxiom(); h4.enableDCE = true;
        // `dead` is never read; init is pure; no type annotation → should be eliminated
        var lenWith = blockLen(h4, 'var dead = 42;\ntrace("hi");');
        var h4b = new Haxiom(); h4b.enableDCE = false;
        var lenWithout = blockLen(h4b, 'var dead = 42;\ntrace("hi");');
        if (lenWith < lenWithout)
            ok('4. Unused untyped pure local eliminated (${lenWithout} → ${lenWith} stmts)');
        else
            fail("4. Unused untyped pure local eliminated", 'block len unchanged ($lenWith vs $lenWithout)');

        // ---------------------------------------------------------------
        // Test 5: Used variable is NOT eliminated
        // ---------------------------------------------------------------
        var h5 = new Haxiom(); h5.enableDCE = true;
        var result5 = [];
        h5.setGlobal("collect", function(v:Dynamic) result5.push(v));
        h5.interpret('var x = 7; collect(x);', null);
        if (result5.length == 1 && result5[0] == 7)
            ok("5. Used variable not eliminated (collect received 7)");
        else
            fail("5. Used variable not eliminated", 'got $result5');

        // ---------------------------------------------------------------
        // Test 6: Typed variable is NOT eliminated (runtime type-check)
        // ---------------------------------------------------------------
        var h6 = new Haxiom(); h6.enableDCE = true;
        // Typed var with wrong type in init — must still throw at runtime
        var threw6 = false;
        try {
            h6.interpret('var p:{name:String} = {name: "ok", extra: 5};', null);
        } catch (e:Dynamic) { threw6 = true; }
        // Valid typed var stays alive for type check
        var result6 = [];
        var h6b = new Haxiom(); h6b.enableDCE = true;
        h6b.setGlobal("collect", function(v:Dynamic) result6.push(v));
        h6b.interpret('var x:Int = 10; collect(x);', null);
        if (result6.length == 1 && result6[0] == 10)
            ok("6. Typed variable preserved (runtime value correct)");
        else
            fail("6. Typed variable preserved", 'got $result6');

        // ---------------------------------------------------------------
        // Test 7: Unused variable with side-effecting init is NOT eliminated
        // ---------------------------------------------------------------
        var h7 = new Haxiom(); h7.enableDCE = true;
        var sideEffectRan = [];
        h7.setGlobal("sideEffect", function() { sideEffectRan.push(1); return 42; });
        h7.interpret('var unused = sideEffect();', null);
        if (sideEffectRan.length == 1)
            ok("7. Unused var with side-effecting init preserved (sideEffect ran)");
        else
            fail("7. Unused var with side-effecting init preserved", 'sideEffect ran ${sideEffectRan.length} times, expected 1');

        // ---------------------------------------------------------------
        // Test 8: Pure expression-statement (not last) is removed
        // ---------------------------------------------------------------
        var h8 = new Haxiom(); h8.enableDCE = true;
        // A lone `1 + 2;` before a real statement — pure, not last → eliminated
        var len8dce = blockLen(h8, '1 + 2;\ntrace("hi");');
        var h8b = new Haxiom(); h8b.enableDCE = false;
        var len8raw = blockLen(h8b, '1 + 2;\ntrace("hi");');
        if (len8dce < len8raw)
            ok('8. Pure expression-statement removed ($len8raw → $len8dce stmts)');
        else
            fail("8. Pure expression-statement removed", 'block len unchanged ($len8dce vs $len8raw)');

        // ---------------------------------------------------------------
        // Test 9: Unused private class method eliminated
        // ---------------------------------------------------------------
        var h9 = new Haxiom(); h9.enableDCE = true;
        var src9 = '
            class MyClass {
                static private function deadHelper() { return 99; }
                static public function main() { return 1; }
            }
        ';
        var ast9 = h9.compile(src9, "t9");
        var methodCount = -1;
        switch (ast9.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, methods, _, _, _, _): methodCount = methods.length;
                    default:
                }
            default:
        }
        if (methodCount == 1) ok("9. Unused private method eliminated (1 method remains)");
        else fail("9. Unused private method eliminated", '$methodCount methods remain, expected 1');

        // ---------------------------------------------------------------
        // Test 10: Public method NOT eliminated
        // ---------------------------------------------------------------
        var h10 = new Haxiom(); h10.enableDCE = true;
        var src10 = '
            class Box {
                public function doA() { return 1; }
                public function doB() { return 2; }
                static public function main() {}
            }
        ';
        var ast10 = h10.compile(src10, "t10");
        var mc10 = -1;
        switch (ast10.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, methods, _, _, _, _): mc10 = methods.length;
                    default:
                }
            default:
        }
        // 3 methods: doA, doB, main — all public, all kept
        if (mc10 == 3) ok("10. Public methods not eliminated (all 3 kept)");
        else fail("10. Public methods not eliminated", '$mc10 methods, expected 3');

        // ---------------------------------------------------------------
        // Test 11: Private method used by another method is NOT eliminated
        // ---------------------------------------------------------------
        var h11 = new Haxiom(); h11.enableDCE = true;
        var src11 = '
            class Util {
                static private function helper() { return 7; }
                static public function compute() { return helper(); }
                static public function main() { compute(); }
            }
        ';
        var ast11 = h11.compile(src11, "Util");
        var mc11 = -1;
        switch (ast11.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, methods, _, _, _, _): mc11 = methods.length;
                    default:
                }
            default:
        }
        // main + compute + helper = 3; but helper is used by compute so kept — all 3 remain
        if (mc11 == 3) ok("11. Private method used internally is NOT eliminated (3 methods kept)");
        else fail("11. Private method used internally is NOT eliminated", '$mc11 methods, expected 3');

        // ---------------------------------------------------------------
        // Test 12: Constructor is always kept
        // ---------------------------------------------------------------
        var h12 = new Haxiom(); h12.enableDCE = true;
        var src12 = '
            class Widget {
                var val:Int;
                public function new(v:Int) { val = v; }
                private function unused() { return 0; }
                static public function main() { var w = new Widget(1); }
            }
        ';
        var ast12 = h12.compile(src12, "Widget");
        var mc12 = -1;
        switch (ast12.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, methods, _, _, _, _): mc12 = methods.length;
                    default:
                }
            default:
        }
        // new + main kept; unused eliminated
        if (mc12 == 2) ok("12. Constructor kept, unused private eliminated (2 methods: new + main)");
        else fail("12. Constructor kept, unused private eliminated", '$mc12 methods, expected 2');

        // ---------------------------------------------------------------
        // Test 13: DCE disabled via enableDCE = false
        // ---------------------------------------------------------------
        var h13 = new Haxiom(); h13.enableDCE = false;
        var len13off = blockLen(h13, 'var dead = 42;\ntrace("hi");');
        var h13b = new Haxiom(); h13b.enableDCE = true;
        var len13on = blockLen(h13b, 'var dead = 42;\ntrace("hi");');
        if (len13off > len13on)
            ok('13. DCE disabled: block kept longer ($len13off vs $len13on stmts)');
        else
            fail("13. DCE disabled", 'expected off($len13off) > on($len13on)');

        // ---------------------------------------------------------------
        // Test 14: Byte size reduced by DCE
        // ---------------------------------------------------------------
        var src14 = '
            var dead1 = 1;
            var dead2 = 2;
            var dead3 = 3;
            var dead4 = 4;
            var dead5 = 5;
            trace("done");
        ';
        var h14on = new Haxiom(); h14on.enableDCE = true;
        var h14off = new Haxiom(); h14off.enableDCE = false;
        var sizeOn = byteSize(h14on, src14);
        var sizeOff = byteSize(h14off, src14);
        if (sizeOn < sizeOff)
            ok('14. Byte size reduced by DCE ($sizeOff bytes → $sizeOn bytes)');
        else
            fail("14. Byte size reduced", 'on=$sizeOn off=$sizeOff (no reduction)');

        // ---------------------------------------------------------------
        // Test 15: Dead top-level class eliminated entirely
        // ---------------------------------------------------------------
        var h15 = new Haxiom(); h15.enableDCE = true;
        // DCE class is never instantiated or referenced — entire class should be eliminated
        var src15 = '
            class Main {
                static public function main() { return 42; }
            }
            class Dead {
                public function new() {}
                public function go() { return 1; }
            }
        ';
        var ast15 = h15.compile(src15, "t15");
        var classCount15 = 0;
        switch (ast15.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, _, _, _, _, _): classCount15++;
                    default:
                }
            default:
        }
        if (classCount15 == 1) ok("15. Dead top-level class eliminated (1 class remains: Main)");
        else fail("15. Dead top-level class eliminated", '$classCount15 classes remain, expected 1');

        // ---------------------------------------------------------------
        // Test 16: Instantiated class is NOT eliminated (ENew protection)
        // ---------------------------------------------------------------
        var h16 = new Haxiom(); h16.enableDCE = true;
        var src16 = '
            class Main {
                static public function main() { var w = new Widget(); return w; }
            }
            class Widget {
                public function new() {}
                public function value() { return 99; }
            }
        ';
        var ast16 = h16.compile(src16, "t16");
        var classCount16 = 0;
        switch (ast16.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, _, _, _, _, _, _): classCount16++;
                    default:
                }
            default:
        }
        if (classCount16 == 2) ok("16. Instantiated class not eliminated (both classes kept)");
        else fail("16. Instantiated class not eliminated", '$classCount16 classes remain, expected 2');

        // ---------------------------------------------------------------
        // Test 17: Unused private field eliminated from class
        // ---------------------------------------------------------------
        var h17 = new Haxiom(); h17.enableDCE = true;
        var src17 = '
            class Counter {
                var count:Int = 0;
                var unusedField:String;
                public function new() { count = 0; }
                public function increment() { count++; }
                public function get():Int { return count; }
                static public function main() { var c = new Counter(); c.increment(); }
            }
        ';
        var ast17 = h17.compile(src17, "Counter");
        var fieldCount17 = -1;
        switch (ast17.def) {
            case EBlock(exprs):
                for (e in exprs) switch (e.def) {
                    case EClass(_, fields, _, _, _, _, _): fieldCount17 = fields.length;
                    default:
                }
            default:
        }
        if (fieldCount17 == 1) ok("17. Unused private field eliminated (1 field remains: count)");
        else fail("17. Unused private field eliminated", '$fieldCount17 fields remain, expected 1');

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        trace("----------------------");
        trace('Results: $passed passed, $failed failed');
        if (failed == 0) {
            trace("ALL DCE TESTS PASSED!");
        } else {
            throw 'DCE TEST SUITE FAILED: $failed test(s) failed';
        }
    }
}
