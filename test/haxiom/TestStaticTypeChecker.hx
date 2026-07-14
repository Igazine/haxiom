package haxiom;

/**
 * TestStaticTypeChecker — verifies that Haxiom.compile(src, file, true) catches
 * type-mismatch errors at compile time rather than runtime.
 * 
 * Tests cover:
 *   1. Array<T>.push() with wrong element type
 *   2. List<T>.add() with wrong element type
 *   3. Map<K,V>.set() with wrong key type
 *   4. Map<K,V>.set() with wrong value type
 *   5. Anonymous struct assigned to typedef with wrong field type
 *   6. Generic enum constructor with wrong argument type
 *   7. Generic class constructor with wrong argument type
 *   8. Valid code passes without errors (no false positives)
 *   9. Static type checking disabled by default
 */
class TestStaticTypeChecker {

    static public function runTests() {
        trace("Static Type Checker Verification Suite");
        trace("---------------------------------------");

        var haxiom = new haxiom.Haxiom();
        var passed = 0;
        var failed = 0;

        // Helper: expect the script to throw a CompileException when staticTypes=true
        function expectTypeError(label:String, src:String):Void {
            try {
                haxiom.compile(src, label, true);
                trace('FAILURE: $label — expected CompileException but none was thrown');
                failed++;
            } catch (e:haxiom.CompileException) {
                trace('SUCCESS: $label — caught expected CompileException: ${e.message}');
                passed++;
            } catch (e:Dynamic) {
                trace('SUCCESS: $label — caught expected error: $e');
                passed++;
            }
        }

        // Helper: expect the script to compile cleanly (no errors)
        function expectNoError(label:String, src:String):Void {
            try {
                haxiom.compile(src, label, true);
                trace('SUCCESS: $label — compiled without errors');
                passed++;
            } catch (e:Dynamic) {
                trace('FAILURE: $label — unexpected error: $e');
                failed++;
            }
        }

        // ---------------------------------------------------------------
        // 1. Array<Int>.push("hello") should fail
        // ---------------------------------------------------------------
        expectTypeError("Array push wrong type",
            'var a:Array<Int> = [];\na.push("hello");'
        );

        // ---------------------------------------------------------------
        // 2. List<String>.add(5) should fail
        // ---------------------------------------------------------------
        expectTypeError("List add wrong type",
            'var l:List<String> = new List();\nl.add(5);'
        );

        // ---------------------------------------------------------------
        // 3. Map<Int,String>.set("key", ...) — wrong key type
        // ---------------------------------------------------------------
        expectTypeError("Map set wrong key type",
            'var m:Map<Int, String> = new Map();\nm.set("hello", "world");'
        );

        // ---------------------------------------------------------------
        // 4. Map<Int,String>.set(1, 42) — wrong value type
        // ---------------------------------------------------------------
        expectTypeError("Map set wrong value type",
            'var m:Map<Int, String> = new Map();\nm.set(1, 42);'
        );

        // ---------------------------------------------------------------
        // 5. Anonymous struct incompatible with typedef
        // ---------------------------------------------------------------
        expectTypeError("Typedef struct field type mismatch",
            'typedef MyType<A, B> = { key: A, value: B }\n' +
            'var t:MyType<String, Int> = { key: 5, value: 5 };'
            // key should be String but we assign Int(5)
        );

        // ---------------------------------------------------------------
        // 6. Generic enum constructor: MyEnum.Fail("hello") where T=Int (typed var required)
        // ---------------------------------------------------------------
        // Note: without explicit var type annotation T is unbound, so no error is possible.
        // The typed-var variant ensures proper binding:
        expectTypeError("Generic enum constructor wrong argument (typed var)",
            'enum MyEnum<T> { Ok; Fail(value:T); }\n' +
            'var e:MyEnum<Int> = MyEnum.Fail("hello");'
        );

        // ---------------------------------------------------------------
        // 7. Generic class constructor: new MyClass<Int>("hello")
        // ---------------------------------------------------------------
        expectTypeError("Generic class constructor wrong argument",
            'class MyClass<T> {\n' +
            '  var value:T;\n' +
            '  public function new(initValue:T) { value = initValue; }\n' +
            '}\n' +
            'var c = new MyClass<Int>("hello");'
        );

        // ---------------------------------------------------------------
        // 8. Valid code should not trigger false positives
        // ---------------------------------------------------------------
        expectNoError("Valid Array<Int>.push(Int)",
            'var a:Array<Int> = [];\na.push(42);'
        );

        expectNoError("Valid List<String>.add(String)",
            'var l:List<String> = new List();\nl.add("hello");'
        );

        expectNoError("Valid Map<String,Int>.set(String,Int)",
            'var m:Map<String, Int> = new Map();\nm.set("key", 100);'
        );

        expectNoError("Valid typedef struct",
            'typedef Point = { x:Float, y:Float }\n' +
            'var p:Point = { x: 1.0, y: 2.0 };'
        );

        expectNoError("Int widening to Float",
            'var f:Float = 5;'  // Int -> Float widening is allowed
        );

        expectNoError("Valid generic class constructor",
            'class Box<T> {\n' +
            '  var val:T;\n' +
            '  public function new(v:T) { val = v; }\n' +
            '}\n' +
            'var b = new Box<String>("hello");'
        );

        expectNoError("Valid enum constructor",
            'enum Result<T> { Ok(v:T); Err(msg:String); }\n' +
            'var r = Result.Ok(42);'
        );

        expectNoError("Implicit Future wrapping and unwrapping",
            'import haxiom.guest.Future;\n' +
            'class MyService {\n' +
            '  public static function getAge():Int {\n' +
            '    var res = HaxiomHost.await(getDelay());\n' +
            '    return res;\n' +
            '  }\n' +
            '  public static function getDelay():Future<Int> {\n' +
            '    return null;\n' +
            '  }\n' +
            '}\n' +
            'var f:Future<Int> = MyService.getAge();\n' +
            'var val:Int = HaxiomHost.await(f);'
        );

        // ---------------------------------------------------------------
        // 10. Accessing private fields from outside the class should fail
        // ---------------------------------------------------------------
        expectTypeError("Accessing private field",
            'class Person {\n' +
            '    private var age:Int = 10;\n' +
            '    public function new() {}\n' +
            '}\n' +
            'var p = new Person();\n' +
            'trace(p.age);'
        );

        // ---------------------------------------------------------------
        // 11. Accessing private methods from outside the class should fail
        // ---------------------------------------------------------------
        expectTypeError("Accessing private method",
            'class Person {\n' +
            '    private function getSecret():Int { return 42; }\n' +
            '    public function new() {}\n' +
            '}\n' +
            'var p = new Person();\n' +
            'p.getSecret();'
        );

        // ---------------------------------------------------------------
        // 12. Declaring class reading its own private fields should pass
        // ---------------------------------------------------------------
        expectNoError("Self class private access",
            'class Person {\n' +
            '    private var age:Int = 10;\n' +
            '    public function new() {}\n' +
            '    public function showAge():Void {\n' +
            '        trace(age);\n' +
            '    }\n' +
            '}'
        );

        // ---------------------------------------------------------------
        // 13. Subclass accessing parent private fields should pass
        // ---------------------------------------------------------------
        expectNoError("Subclass private access",
            'class Base {\n' +
            '    private var secret:Int = 99;\n' +
            '    public function new() {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    public function printSecret():Void {\n' +
            '        trace(secret);\n' +
            '    }\n' +
            '}'
        );

        // ---------------------------------------------------------------
        // 14. Declaring interface-required method as private should fail
        // ---------------------------------------------------------------
        expectTypeError("Private method implementing interface",
            'interface IRunnable {\n' +
            '    function run():Void;\n' +
            '}\n' +
            'class Runner implements IRunnable {\n' +
            '    public function new() {}\n' +
            '    private function run():Void {}\n' +
            '}'
        );

        // ---------------------------------------------------------------
        // 15. Overriding a method without override keyword should fail
        // ---------------------------------------------------------------
        expectTypeError("Missing override keyword",
            'class Base {\n' +
            '    public function new() {}\n' +
            '    public function show():Void {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    public function show():Void {}\n' +
            '}'
        );

        // 16. Marking a non-existent parent method override should fail
        // ---------------------------------------------------------------
        expectTypeError("Bad override keyword",
            'class Base {\n' +
            '    public function new() {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    override public function show():Void {}\n' +
            '}'
        );

        // 17. Overriding method with signature mismatch (arguments) should fail
        // ---------------------------------------------------------------
        expectTypeError("Override argument count mismatch",
            'class Base {\n' +
            '    public function new() {}\n' +
            '    public function show(x:Int):Void {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    override public function show(x:Int, y:Int):Void {}\n' +
            '}'
        );

        // 18. Overriding method with signature mismatch (argument type) should fail
        // ---------------------------------------------------------------
        expectTypeError("Override argument type mismatch",
            'class Base {\n' +
            '    public function new() {}\n' +
            '    public function show(x:Int):Void {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    override public function show(x:String):Void {}\n' +
            '}'
        );

        // 19. Correct override should pass
        // ---------------------------------------------------------------
        expectNoError("Correct override",
            'class Base {\n' +
            '    public function new() {}\n' +
            '    public function show(x:Int):Void {}\n' +
            '}\n' +
            'class Derived extends Base {\n' +
            '    override public function show(x:Int):Void {}\n' +
            '}'
        );

        // 20. Instantiating an abstract class should fail
        // ---------------------------------------------------------------
        expectTypeError("Instantiating abstract class",
            'abstract class Animal {\n' +
            '    public function new() {}\n' +
            '}\n' +
            'var a = new Animal();'
        );

        // 21. Class failing to implement inherited abstract method should fail
        // ---------------------------------------------------------------
        expectTypeError("Missing abstract implementation",
            'abstract class Animal {\n' +
            '    public function new() {}\n' +
            '    abstract public function sound():Void;\n' +
            '}\n' +
            'class Dog extends Animal {\n' +
            '    public function new() {}\n' +
            '}'
        );

        // 22. Concrete class correctly implementing abstract method should pass
        // ---------------------------------------------------------------
        expectNoError("Correct abstract implementation",
            'abstract class Animal {\n' +
            '    public function new() {}\n' +
            '    abstract public function sound():Void;\n' +
            '}\n' +
            'class Dog extends Animal {\n' +
            '    public function new() {}\n' +
            '    public function sound():Void {}\n' +
            '}'
        );

        // 23. Implementing abstract method with override keyword should fail
        // ---------------------------------------------------------------
        expectTypeError("Override on abstract method implementation",
            'abstract class Animal {\n' +
            '    public function new() {}\n' +
            '    abstract public function sound():Void;\n' +
            '}\n' +
            'class Dog extends Animal {\n' +
            '    public function new() {}\n' +
            '    override public function sound():Void {}\n' +
            '}'
        );

        // ---------------------------------------------------------------
        // 24. Static type checking is disabled by default
        // ---------------------------------------------------------------
        trace("--- Testing static checking is OFF by default ---");
        try {
            // This WOULD fail with staticTypes=true, but should succeed without it
            haxiom.compile('var a:Array<Int> = [];\na.push("hello");', "default_check");
            trace("SUCCESS: Default compile (no staticTypes) passes with type errors — checking is opt-in");
            passed++;
        } catch (e:Dynamic) {
            trace("FAILURE: compile() should not type-check by default. Got: " + e);
            failed++;
        }

        // ---------------------------------------------------------------
        // Final summary
        // ---------------------------------------------------------------
        trace('---------------------------------------');
        trace('Results: ${passed} passed, ${failed} failed');
        if (failed == 0) {
            trace("ALL STATIC TYPE CHECKER TESTS PASSED!");
        } else {
            throw 'STATIC TYPE CHECKER TEST SUITE FAILED: ${failed} test(s) failed';
        }
    }
}
