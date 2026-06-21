package haxiom;

import haxiom.AST.TypeDecl;
import haxiom.Interp.Scope;

class MyBaseClass {
	public function new() {}
}
class MySubClass extends MyBaseClass {
	public function new() { super(); }
}

interface IMyInterface {}
class MyImplementingClass implements IMyInterface {
	public function new() {}
}

class TestTypeSystem {
	public static function main() {
		var interp = new Interp();
		interp.importWhitelist.push("haxiom.*");
		var scope = new Scope(null);

		// Helper assertion
		function assertCompat(val:Dynamic, type:TypeDecl, expectedCompat:Bool) {
			var success = true;
			try {
				TypeSystem.checkType(interp, val, type, scope);
			} catch (e:Dynamic) {
				success = false;
			}
			if (success != expectedCompat) {
				throw 'Assertion Failed: value $val check against type $type expected compat $expectedCompat but got $success';
			}
		}

		trace("Starting TypeSystem Standalone tests...");
		trace("resolveClass haxiom.MyBaseClass: " + Type.resolveClass("haxiom.MyBaseClass"));
		trace("isImportWhitelisted: " + interp.isImportWhitelisted("haxiom.MyBaseClass"));

		// 1. Primitive Tests
		assertCompat(42, TPath(["Int"], []), true);
		assertCompat("Hello", TPath(["Int"], []), false);
		assertCompat("Hello", TPath(["String"], []), true);
		assertCompat(true, TPath(["Bool"], []), true);
		assertCompat(1.23, TPath(["Float"], []), true);

		// 2. Class and Subclass Tests
		var baseInst = new MyBaseClass();
		var subInst = new MySubClass();
		
		// Declare classes in scope so resolveTypePath can find them
		scope.declare("haxiom.MyBaseClass", MyBaseClass);
		scope.declare("haxiom.MySubClass", MySubClass);

		assertCompat(baseInst, TPath(["haxiom", "MyBaseClass"], []), true);
		assertCompat(subInst, TPath(["haxiom", "MyBaseClass"], []), true);
		assertCompat(baseInst, TPath(["haxiom", "MySubClass"], []), false);
		assertCompat(subInst, TPath(["haxiom", "MySubClass"], []), true);

		// 3. Interface Tests
		var implInst = new MyImplementingClass();
		scope.declare("haxiom.IMyInterface", IMyInterface);
		assertCompat(implInst, TPath(["haxiom", "IMyInterface"], []), true);

		trace("SUCCESS: All TestTypeSystem standalone tests passed!");
	}
}
