package haxiom;

import haxiom.Haxiom;
import haxiom.AST;

class TestCompilationFeatures {
    public static function main() {
        runTests();
    }

    public static function runTests() {
        trace("Starting Haxiom Preprocessor, Optional Types, and Macros Verification Suite...");
        
        testPreprocessor();
        testOptionalFields();
        testMacros();
        testInline();
        testInstructionLimit();
        testComprehensionsAndInterpolation();
        testRestArguments();
        testFinals();
        testStrictSemicolons();
        #if sys
        testModularity();
        #end
        
        trace("SUCCESS: All Haxiom preprocessor, optional type, macro, instruction limit, comprehension, rest argument, final, and strict semicolon" + #if sys ", and modularity" + #end " tests passed!");
    }

    static function testPreprocessor() {
        var engine = new Haxiom();
        engine.useVM = true;

        // Test basic #if/#else with haxiom_script
        var script = '
            var x = 0;
            #if haxiom_script
            x = 100;
            #else
            x = 200;
            #end
            x;
        ';
        var res:Int = engine.interpret(script);
        if (res != 100) throw "testPreprocessor basic #if failed: expected 100, got " + res;

        // Test haxiom.script backward compatibility
        var scriptDot = '
            var x = 0;
            #if haxiom.script
            x = 150;
            #else
            x = 250;
            #end
            x;
        ';
        var resDot:Int = engine.interpret(scriptDot);
        if (resDot != 150) throw "testPreprocessor haxiom.script compatibility failed: expected 150, got " + resDot;

        // Test basic #else branch using negated condition
        var script2 = '
            var x = 0;
            #if !haxiom_script
            x = 100;
            #else
            x = 200;
            #end
            x;
        ';
        var res2:Int = engine.interpret(script2);
        if (res2 != 200) throw "testPreprocessor basic #else failed: expected 200, got " + res2;

        // Test #elseif branch
        var script3 = '
            var x = 0;
            #if !haxiom_script
            x = 10;
            #elseif haxiom.script
            x = 20;
            #else
            x = 30;
            #end
            x;
        ';
        var res3:Int = engine.interpret(script3);
        if (res3 != 20) throw "testPreprocessor #elseif failed: expected 20, got " + res3;

        // Test nested #if directives
        var script4 = '
            var x = 0;
            #if haxiom_script
                #if !haxiom.script
                x = 1;
                #else
                x = 2;
                #end
            #else
            x = 3;
            #end
            x;
        ';
        var res4:Int = engine.interpret(script4);
        if (res4 != 2) throw "testPreprocessor nested #if failed: expected 2, got " + res4;

        // Test preprocessor expression evaluation with &&, ||, !
        var script5 = '
            var x = 0;
            #if (haxiom_script && !haxiom.script)
            x = 500;
            #else
            x = 600;
            #end
            x;
        ';
        var res5:Int = engine.interpret(script5);
        if (res5 != 600) throw "testPreprocessor expression && ! failed: expected 600, got " + res5;

        // Test #error compilation failure in active branch
        var caughtError = false;
        try {
            var scriptErr = '
                #if haxiom_script
                #error "This is an expected compilation error!"
                #end
            ';
            engine.interpret(scriptErr);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("This is an expected compilation error!") != -1) {
                caughtError = true;
            }
        }
        if (!caughtError) throw "testPreprocessor #error failed: expected compilation error to be thrown";

        // Test #error inside inactive branch is ignored
        var scriptErrIgnore = '
            #if !haxiom_script
            #error "Should not throw!"
            #end
            var success = 42;
            success;
        ';
        var resErr:Int = engine.interpret(scriptErrIgnore);
        if (resErr != 42) throw "testPreprocessor inactive #error failed: expected 42, got " + resErr;

        // Test that using an unknown/unsupported conditional throws a compilation error
        var caughtForbidden = false;
        try {
            var scriptForbidden = '
                #if openfl
                var x = 1;
                #end
            ';
            engine.interpret(scriptForbidden);
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            if (errStr.indexOf("Only the \"haxiom_script\" and \"haxiom.script\" preprocessor conditionals are allowed") != -1) {
                caughtForbidden = true;
            }
        }
        if (!caughtForbidden) throw "Expected compilation error for forbidden preprocessor conditional 'openfl'";

        // Test that root-level extern function/var throws compile-time exception
        var caughtExternTop = false;
        try {
            engine.interpret("extern function foo():Void;");
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            if (errStr.indexOf("Extern variables and functions must be declared inside a class or must be extern classes") != -1) {
                caughtExternTop = true;
            }
        }
        if (!caughtExternTop) throw "Expected compile-time error for root-level 'extern' function usage";

        // Test that extern class and extern class-member compile cleanly
        engine.interpret("extern class MockClass {}");
        engine.interpret("
            class MockClass {
                extern function foo():Void;
            }
        ");

        // Test that using the 'extern' keyword throws a compile-time exception (expression-level)
        var caughtExternExpr = false;
        try {
            engine.interpret("var x = extern;");
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            if (errStr.indexOf("Haxe externs are not supported in Haxiom guest scripts") != -1) {
                caughtExternExpr = true;
            }
        }
        if (!caughtExternExpr) throw "Expected compile-time error for expression-level 'extern' keyword usage";

        trace("SUCCESS: Preprocessor tests passed.");
    }

    static function testOptionalFields() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = '
            typedef User = {
                var name:String;
                var ?age:Int;
            }
            
            class Validator {
                public static function check(u:User):String {
                    return u.name;
                }
            }
        ';
        engine.interpret(script);

        // Verify successful validation with optional field absent
        var checkFunc:Dynamic = engine.interpret("Validator.check;");
        var res1 = checkFunc({ name: "Alice" });
        if (res1 != "Alice") throw "testOptionalFields missing opt field failed: expected 'Alice', got " + res1;

        // Verify successful validation with optional field present
        var res2 = checkFunc({ name: "Bob", age: 25 });
        if (res2 != "Bob") throw "testOptionalFields with opt field failed: expected 'Bob', got " + res2;

        // Verify type check failure when optional field has wrong type
        var caughtWrongType = false;
        try {
            checkFunc({ name: "Bob", age: "twenty-five" });
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("Type mismatch in field \"age\"") != -1) {
                caughtWrongType = true;
            }
        }
        if (!caughtWrongType) throw "testOptionalFields wrong type failed: expected type mismatch exception";

        // Verify type check failure when required field is missing
        var caughtMissingField = false;
        try {
            checkFunc({ age: 30 });
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("Type mismatch: object is missing field \"name\"") != -1) {
                caughtMissingField = true;
            }
        }
        if (!caughtMissingField) throw "testOptionalFields missing required field failed: expected missing field exception";

        trace("SUCCESS: Optional fields tests passed.");
    }

    static function testMacros() {
        var engine = new Haxiom();
        engine.useVM = true;

        // Define a macro static method inside a class
        var script = '
            import haxiom.AST.ExprDef;
            
            class MyMacros {
                @:haxiom.macro
                public static function double(e) {
                    // Duplicate/add the expression to itself: e + e
                    return {
                        def: ExprDef.EBinop("+", e, e),
                        pos: e.pos
                    };
                }

                @:haxiom.macro
                public static function makeInt(e) {
                    return {
                        def: ExprDef.EValue(42),
                        pos: e.pos
                    };
                }
            }

            class UsageClass {
                public static function run() {
                    var x = MyMacros.double(5); // Should expand to 5 + 5
                    var y = MyMacros.makeInt("unused"); // Should expand to 42
                    return x + y;
                }
            }
            UsageClass.run();
        ';

        var res:Int = engine.interpret(script);
        if (res != 52) throw "testMacros failed: expected 52, got " + res;

        trace("SUCCESS: Macro tests passed.");
    }

    static function testInline() {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = '
            class InlineDemo {
                static inline function getOffset():Int {
                    return 100;
                }
                
                public inline function add(a:Int, b:Int):Int {
                    return a + b + getOffset();
                }
            }
            
            inline function localHelper(x:Int):Int {
                return x * 2;
            }

            var inst = new InlineDemo();
            inst.add(10, 20) + localHelper(5);
        ';

        var res:Int = engine.interpret(script);
        if (res != 140) throw "testInline failed: expected 140, got " + res;

        // Test AST mode too
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        var resAST:Int = engineAST.interpret(script);
        if (resAST != 140) throw "testInline (AST) failed: expected 140, got " + resAST;

        // Test Modulo Assign %=
        var pctScript = '
            var x = 10;
            x %= 3;
            x;
        ';
        var resPct:Int = engine.interpret(pctScript);
        if (resPct != 1) throw "testPercentAssign (VM) failed: expected 1, got " + resPct;
        var resPctAST:Int = engineAST.interpret(pctScript);
        if (resPctAST != 1) throw "testPercentAssign (AST) failed: expected 1, got " + resPctAST;

        trace("SUCCESS: Inline modifier and Modulo Assign tests passed.");
    }

    static function testInstructionLimit() {
        var infiniteLoopScript = '
            var count = 0;
            while (true) {
                count++;
            }
        ';

        // 1. Test VM Mode
        var engineVM = new Haxiom();
        engineVM.useVM = true;
        engineVM.maxInstructions = 1000;
        
        var caughtVM = false;
        try {
            engineVM.interpret(infiniteLoopScript);
        } catch (e:haxiom.ScriptException) {
            if (StringTools.contains(e.message, "Instruction limit exceeded")) {
                caughtVM = true;
            } else {
                trace("Unexpected exception VM: " + e);
            }
        }
        if (!caughtVM) throw "testInstructionLimit (VM) failed: did not catch instruction limit exception";

        // 2. Test AST Mode
        var engineAST = new Haxiom();
        engineAST.useVM = false;
        engineAST.maxInstructions = 1000;
        
        var caughtAST = false;
        try {
            engineAST.interpret(infiniteLoopScript);
        } catch (e:haxiom.ScriptException) {
            if (StringTools.contains(e.message, "Instruction limit exceeded")) {
                caughtAST = true;
            } else {
                trace("Unexpected exception AST: " + e);
            }
        }
        if (!caughtAST) throw "testInstructionLimit (AST) failed: did not catch instruction limit exception";

        trace("SUCCESS: Instruction limit safeguard tests passed.");
    }

    static function testComprehensionsAndInterpolation() {
        var engine = new Haxiom();
        
        for (useVM in [true, false]) {
            engine.useVM = useVM;
            var mode = useVM ? "VM" : "AST";
            
            // 1. String interpolation for single-quotes
            var interpScript = "
                var name = 'Tamas';
                var person = {name: 'Tamas', age: 44};
                var s1 = 'hello $name';
                var s2 = 'hello ${person.name}';
                s1 + '|' + s2;
            ";
            var resInterp:String = engine.interpret(interpScript);
            if (resInterp != "hello Tamas|hello Tamas") {
                throw "testComprehensionsAndInterpolation (" + mode + ") string interpolation failed: got " + resInterp;
            }

            // 2. Array comprehension
            var arrayScript = "
                var a = [for (i in 0...10) i];
                var i = 0;
                var b = [while (i < 10) i++];
                a.join(',') + '|' + b.join(',');
            ";
            var resArray:String = engine.interpret(arrayScript);
            if (resArray != "0,1,2,3,4,5,6,7,8,9|0,1,2,3,4,5,6,7,8,9") {
                throw "testComprehensionsAndInterpolation (" + mode + ") array comprehension failed: got " + resArray;
            }

            // 3. Map comprehension
            var mapScript = "
                var a = [for (i in 0...5) i => 'number ${i}'];
                var i = 0;
                var b = [while (i < 5) i => 'number ${i++}'];
                a.get(0) + '|' + a.get(4) + '|' + b.get(0) + '|' + b.get(4);
            ";
            var resMap:String = engine.interpret(mapScript);
            if (resMap != "number 0|number 4|number 0|number 4") {
                throw "testComprehensionsAndInterpolation (" + mode + ") map comprehension failed: got " + resMap;
            }
        }
        
        trace("SUCCESS: Comprehensions and interpolation tests passed.");
    }

    static function testRestArguments() {
        var engine = new Haxiom();

        for (useVM in [true, false]) {
            engine.useVM = useVM;
            var mode = useVM ? "VM" : "AST";

            // 1. Basic rest arguments
            var script = "
                function log(...args:Dynamic) {
                    var res = '';
                    for (a in args) {
                        res += Std.string(a) + ',';
                    }
                    return res;
                }
                log('hello', 'world', 44);
            ";
            var res:String = engine.interpret(script);
            if (res != "hello,world,44,") {
                throw "testRestArguments (" + mode + ") basic failed: expected 'hello,world,44,', got " + res;
            }

            // 2. Typed rest arguments (success)
            var scriptTyped = "
                function sum(...args:Int) {
                    var total = 0;
                    for (a in args) {
                        total += a;
                    }
                    return total;
                }
                sum(1, 2, 3, 4);
            ";
            var resSum:Int = engine.interpret(scriptTyped);
            if (resSum != 10) {
                throw "testRestArguments (" + mode + ") typed sum failed: expected 10, got " + resSum;
            }

            // 3. Typed rest arguments (type mismatch failure)
            var scriptFail = "
                function sum(...args:Int) {
                    return args.length;
                }
                sum(1, 'two', 3);
            ";
            var caughtTypeFail = false;
            try {
                engine.interpret(scriptFail);
            } catch (e:Dynamic) {
                caughtTypeFail = true;
            }
            if (!caughtTypeFail) {
                throw "testRestArguments (" + mode + ") expected type mismatch exception for rest element";
            }

            // 4. Class static method with rest arguments
            var scriptClass = "
                class MathUtil {
                    public static function add(base:Int, ...nums:Int):Int {
                        var res = base;
                        for (n in nums) {
                            res += n;
                        }
                        return res;
                    }
                }
                MathUtil.add(100, 10, 20, 30);
            ";
            var resClass:Int = engine.interpret(scriptClass);
            if (resClass != 160) {
                throw "testRestArguments (" + mode + ") class method failed: expected 160, got " + resClass;
            }
        }

        trace("SUCCESS: Rest arguments tests passed.");
    }

    static function testFinals() {
        for (useVM in [true, false]) {
            var mode = useVM ? "VM" : "AST";

            // 1. Local final variable reassignment
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptLocal = "
                    final x = 42;
                    x = 100;
                ";
                var caughtLocal = false;
                try {
                    engine.interpret(scriptLocal);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign final variable") != -1) {
                        caughtLocal = true;
                    } else {
                        trace("Unexpected local error (" + mode + "): " + e);
                    }
                }
                if (!caughtLocal) {
                    throw "testFinals (" + mode + ") failed to block local final reassignment";
                }
            }

            // 2. Local final variable unary mutating operators
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptUnop = "
                    final count = 10;
                    count++;
                ";
                var caughtUnop = false;
                try {
                    engine.interpret(scriptUnop);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign final variable") != -1) {
                        caughtUnop = true;
                    } else {
                        trace("Unexpected unop error (" + mode + "): " + e);
                    }
                }
                if (!caughtUnop) {
                    throw "testFinals (" + mode + ") failed to block local final increment";
                }
            }

            // 3. Captured final variable reassignment
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptCaptured = "
                    final name = 'Tamas';
                    var f = function() {
                        name = 'John';
                    };
                    f();
                ";
                var caughtCaptured = false;
                try {
                    engine.interpret(scriptCaptured);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign final variable") != -1) {
                        caughtCaptured = true;
                    } else {
                        trace("Unexpected captured error (" + mode + "): " + e);
                    }
                }
                if (!caughtCaptured) {
                    throw "testFinals (" + mode + ") failed to block captured final reassignment";
                }
            }

            // 4. Class member final field outside of constructor
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptMember = "
                    class Person {
                        public final name:String;
                        public function new(n:String) {
                            name = n;
                        }
                        public function setName(n:String) {
                            name = n;
                        }
                    }
                    var p = new Person('Tamas');
                    p.setName('John');
                ";
                var caughtMember = false;
                try {
                    engine.interpret(scriptMember);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign final field") != -1) {
                        caughtMember = true;
                    } else {
                        trace("Unexpected member error (" + mode + "): " + e);
                    }
                }
                if (!caughtMember) {
                    throw "testFinals (" + mode + ") failed to block member final reassignment outside of constructor";
                }
            }

            // 5. Class member final field direct assignment
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptDirect = "
                    class Person {
                        public final name:String;
                        public function new(n:String) {
                            name = n;
                        }
                    }
                    var p = new Person('Tamas');
                    p.name = 'John';
                ";
                var caughtDirect = false;
                try {
                    engine.interpret(scriptDirect);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign final field") != -1) {
                        caughtDirect = true;
                    } else {
                        trace("Unexpected direct error (" + mode + "): " + e);
                    }
                }
                if (!caughtDirect) {
                    throw "testFinals (" + mode + ") failed to block member final direct assignment";
                }
            }

            // 6. Class static final field outside class constructor / definition
            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptStatic = "
                    class Conf {
                        public static final ID = 'xyz';
                        public static function change() {
                            ID = 'abc';
                        }
                    }
                    Conf.change();
                ";
                var caughtStatic = false;
                try {
                    engine.interpret(scriptStatic);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign static final field") != -1) {
                        caughtStatic = true;
                    } else {
                        trace("Unexpected static error (" + mode + "): " + e);
                    }
                }
                if (!caughtStatic) {
                    throw "testFinals (" + mode + ") failed to block static final field reassignment inside class";
                }
            }

            {
                var engine = new Haxiom();
                engine.useVM = useVM;
                var scriptStaticOutside = "
                    class Conf {
                        public static final ID = 'xyz';
                    }
                    Conf.ID = 'abc';
                ";
                var caughtStaticOutside = false;
                try {
                    engine.interpret(scriptStaticOutside);
                } catch (e:Dynamic) {
                    if (Std.string(e).indexOf("Cannot reassign static final field") != -1) {
                        caughtStaticOutside = true;
                    } else {
                        trace("Unexpected static outside error (" + mode + "): " + e);
                    }
                }
                if (!caughtStaticOutside) {
                    throw "testFinals (" + mode + ") failed to block static final field reassignment outside class";
                }
            }
        }

        trace("SUCCESS: Finals and constants tests passed.");
    }

    static function testStrictSemicolons() {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.importWhitelist = null;

        var expectCompileError = function(script:String, label:String) {
            try {
                engine.compile(script);
                throw "Expected compile error for: " + label + " but it passed.";
            } catch (e:Dynamic) {
                var errStr = Std.string(e);
                if (errStr.indexOf("Compile Error") == -1) {
                    throw "Expected compile error for " + label + " but got: " + errStr;
                }
            }
        };

        var expectSuccess = function(script:String, label:String) {
            try {
                engine.compile(script);
            } catch (e:Dynamic) {
                throw "Expected success for " + label + " but got error: " + e;
            }
        };

        // Assert expression statements require semicolons at top-level
        expectCompileError("trace('hello')", "top-level trace without semicolon");
        expectSuccess("trace('hello');", "top-level trace with semicolon");

        // Assert variable declarations require semicolons
        expectCompileError("var x = 1", "var decl without semicolon");
        expectSuccess("var x = 1;", "var decl with semicolon");

        // Assert final declarations require semicolons
        expectCompileError("final y = 2", "final decl without semicolon");
        expectSuccess("final y = 2;", "final decl with semicolon");

        // Assert return/break/continue require semicolons
        expectCompileError("function f() { return 5 }", "return without semicolon");
        expectSuccess("function f() { return 5; }", "return with semicolon");
        
        expectCompileError("while(true) { break }", "break without semicolon");
        expectSuccess("while(true) { break; }", "break with semicolon");

        expectCompileError("while(true) { continue }", "continue without semicolon");
        expectSuccess("while(true) { continue; }", "continue with semicolon");

        // Assert throw statements require semicolons
        expectCompileError("throw 'err'", "throw without semicolon");
        expectSuccess("throw 'err';", "throw with semicolon");

        // Assert package / import / using require semicolons
        expectCompileError("import haxe.Log", "import without semicolon");
        expectSuccess("import haxe.Log;", "import with semicolon");

        // Assert typedef requires a semicolon (optional / match)
        expectSuccess("typedef Point = {x:Int, y:Int}", "typedef of anon structure without semicolon");
        expectSuccess("typedef Point = {x:Int, y:Int};", "typedef of anon structure with semicolon");

        // Assert comprehensions do NOT require semicolons for yield expressions
        expectSuccess("var list = [for (i in 0...5) i];", "array comprehension yield without semicolon");
        expectSuccess("var map = [for (i in 0...5) i => 'val'];", "map comprehension yield without semicolon");

        // Assert if-else branches do NOT require semicolons before else
        expectSuccess("if (true) trace(1) else trace(2);", "if-else branch without semicolon before else");
        expectSuccess("if (true) trace(1); else trace(2);", "if-else branch with semicolon before else");

        trace("SUCCESS: Strict semicolons tests passed.");
    }

    #if sys
    static function deleteDirRecursive(path:String) {
        if (sys.FileSystem.exists(path)) {
            if (sys.FileSystem.isDirectory(path)) {
                for (entry in sys.FileSystem.readDirectory(path)) {
                    deleteDirRecursive(path + "/" + entry);
                }
                sys.FileSystem.deleteDirectory(path);
            } else {
                sys.FileSystem.deleteFile(path);
            }
        }
    }

    static function testModularity() {
        var tempDir = "temp_test_modularity";
        
        // Clean any leftover from previous runs
        deleteDirRecursive(tempDir);
        
        // Create directory structures
        sys.FileSystem.createDirectory(tempDir);
        sys.FileSystem.createDirectory(tempDir + "/mypackage/sub");
        sys.FileSystem.createDirectory(tempDir + "/other");
        
        // Write dependency files
        sys.io.File.saveContent(tempDir + "/mypackage/sub/MyClass.hx", "
            package mypackage.sub;
            
            class MyClass {
                public static function myFunc():String {
                    return 'Hello from MyClass';
                }
            }
        ");
        
        sys.io.File.saveContent(tempDir + "/other/Helper.hx", "
            package other;
            
            class Helper {
                public static function helpMe():Int {
                    #if haxiom_script
                    return 42;
                    #else
                    return 999;
                    #end
                }
            }
        ");
        
        // Write main file
        sys.io.File.saveContent(tempDir + "/Main.hx", "
            import mypackage.sub.MyClass;
            import other.Helper;
            
            class Main {
                public static var resultString:String = '';
                public static var resultInt:Int = 0;
                
                public static function main() {
                    resultString = MyClass.myFunc();
                    resultInt = Helper.helpMe();
                }
            }
        ");
        
        // Run compilation through LibRun
        try {
            haxiom.LibRun.bytecodeCompile(tempDir + "/", "Main.hx");
        } catch (e:Dynamic) {
            deleteDirRecursive(tempDir);
            throw "Failed to compile/bundle modular script: " + e;
        }
        
        var bcPath = tempDir + "/Main.hxbc";
        if (!sys.FileSystem.exists(bcPath)) {
            deleteDirRecursive(tempDir);
            throw "Compiled .hxbc file was not created at " + bcPath;
        }
        
        // Read the compiled bytecode bytes
        var bytes = sys.io.File.getBytes(bcPath);
        
        // Execute the bytecode using a clean Haxiom instance (without filesystem access or moduleResolver)
        var engine = new Haxiom();
        engine.useVM = true;
        engine.importWhitelist = null; // allow all imports (native standard lib or packages)
        
        try {
            engine.executeBytes(bytes);
        } catch (e:Dynamic) {
            trace("DEBUG MODULARITY TEST EXCEPTION: " + e);
            if (Std.isOfType(e, haxiom.ScriptException)) {
                var se:haxiom.ScriptException = cast e;
                trace("ORIGINAL EXCEPTION: " + se.rawValue);
                trace("Formatted stack trace:\n" + se.formattedStackTrace);
                trace("Virtual Stack: " + se.virtualStack);
            }
            trace("Haxe Call Stack: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            deleteDirRecursive(tempDir);
            throw "Execution of bundled bytecode failed: " + e;
        }
        
        // Verify class definitions and static variable updates
        var mainClass = engine.getGlobal("Main");
        if (mainClass == null) {
            deleteDirRecursive(tempDir);
            throw "Main class was not registered in engine globals";
        }
        
        var resString = engine.resolveField(mainClass, "resultString");
        var resInt = engine.resolveField(mainClass, "resultInt");
        
        if (resString != "Hello from MyClass") {
            deleteDirRecursive(tempDir);
            throw "Expected resultString to be 'Hello from MyClass', but got: " + resString;
        }
        
        if (resInt != 42) {
            deleteDirRecursive(tempDir);
            throw "Expected resultInt to be 42, but got: " + resInt;
        }
        
        // Test 2: Local Package Overrides (e.g. mock local file overriding host class)
        // We write a local system file to override/shadow standard class or native FFI.
        // Let's create a local `sys/FileSystem.hx` that overrides standard behavior.
        sys.FileSystem.createDirectory(tempDir + "/sys");
        sys.io.File.saveContent(tempDir + "/sys/FileSystem.hx", "
            package sys;
            
            class FileSystem {
                public static function exists(path:String):Bool {
                    return true; // always true in local override
                }
            }
        ");
        
        sys.io.File.saveContent(tempDir + "/MainOverride.hx", "
            import sys.FileSystem;
            
            class MainOverride {
                public static var checkExists:Bool = false;
                public static function main() {
                    checkExists = FileSystem.exists('completely_fake_path_12345');
                }
            }
        ");
        
        try {
            haxiom.LibRun.bytecodeCompile(tempDir + "/", "MainOverride.hx");
        } catch (e:Dynamic) {
            deleteDirRecursive(tempDir);
            throw "Failed to compile MainOverride: " + e;
        }
        
        var overrideBcPath = tempDir + "/MainOverride.hxbc";
        var overrideBytes = sys.io.File.getBytes(overrideBcPath);
        
        var engineOverride = new Haxiom();
        engineOverride.useVM = true;
        engineOverride.importWhitelist = null;
        engineOverride.executeBytes(overrideBytes);
        
        var mainOverrideClass = engineOverride.getGlobal("MainOverride");
        var checkExistsVal = engineOverride.resolveField(mainOverrideClass, "checkExists");
        if (checkExistsVal != true) {
            deleteDirRecursive(tempDir);
            throw "Expected local override of FileSystem.exists to return true, but got: " + checkExistsVal;
        }
        
        // Test 3: Circular dependency detection
        sys.FileSystem.createDirectory(tempDir + "/circ");
        sys.io.File.saveContent(tempDir + "/circ/A.hx", "
            package circ;
            import circ.B;
            class A {}
        ");
        sys.io.File.saveContent(tempDir + "/circ/B.hx", "
            package circ;
            import circ.A;
            class B {}
        ");
        
        var caughtCirc = false;
        try {
            haxiom.LibRun.bytecodeCompile(tempDir + "/", "circ/A.hx");
        } catch (e:Dynamic) {
            var errStr = Std.string(e);
            if (errStr.indexOf("Circular dependency") != -1) {
                caughtCirc = true;
            } else {
                deleteDirRecursive(tempDir);
                throw "Expected Circular dependency error, but got: " + errStr;
            }
        }
        
        if (!caughtCirc) {
            deleteDirRecursive(tempDir);
            throw "Failed to detect circular dependency between circ.A and circ.B";
        }
        // Test 4: Inline fully qualified package/module name reference bundling
        sys.FileSystem.createDirectory(tempDir + "/fq");
        sys.io.File.saveContent(tempDir + "/fq/Helper.hx", "
            package fq;
            class Helper {
                public static function getValue():Int {
                    return 100;
                }
            }
        ");

        sys.io.File.saveContent(tempDir + "/MainFQ.hx", "
            class MainFQ {
                public static var result:Int = 0;
                public static function main() {
                    result = fq.Helper.getValue();
                }
            }
        ");

        try {
            haxiom.LibRun.bytecodeCompile(tempDir + "/", "MainFQ.hx");
        } catch (e:Dynamic) {
            deleteDirRecursive(tempDir);
            throw "Failed to compile/bundle MainFQ script: " + e;
        }

        var bcPathFQ = tempDir + "/MainFQ.hxbc";
        if (!sys.FileSystem.exists(bcPathFQ)) {
            deleteDirRecursive(tempDir);
            throw "Compiled .hxbc file for MainFQ was not created at " + bcPathFQ;
        }

        var bytesFQ = sys.io.File.getBytes(bcPathFQ);
        var engineFQ = new Haxiom();
        engineFQ.useVM = true;
        engineFQ.importWhitelist = null;

        try {
            engineFQ.executeBytes(bytesFQ);
        } catch (e:Dynamic) {
            deleteDirRecursive(tempDir);
            throw "Execution of MainFQ bytecode failed: " + e;
        }

        var mainFQClass = engineFQ.getGlobal("MainFQ");
        if (mainFQClass == null) {
            deleteDirRecursive(tempDir);
            throw "MainFQ class was not registered in engine globals";
        }

        var resultFQ = engineFQ.resolveField(mainFQClass, "result");
        if (resultFQ != 100) {
            deleteDirRecursive(tempDir);
            throw "Expected resultFQ to be 100, but got: " + resultFQ;
        }

        // Clean up temporary workspace
        deleteDirRecursive(tempDir);
        
        trace("SUCCESS: Modularity and dependency bundling tests passed.");
    }
    #end
}

