package haxiom.bundle;

import haxiom.Haxiom;
import sys.io.File;

class RunBundle {
	public static function main() {
		var engine = new Haxiom();
		engine.useVM = true;
		engine.importWhitelist = null; // Disable sandboxing for standard outputs

		trace("Loading library test bundle bytecode...");
		var bytes = File.getBytes("test/haxiom/bundle/MyLib.hxbc");
		
		trace("Executing library test bundle...");
		engine.executeBytes(bytes);
		
		trace("Resolving MyLib.doSomething closure using engine APIs...");
		var myLibClass:Dynamic = engine.getGlobal("MyLib");
		if (myLibClass == null) {
			throw "MyLib class was not registered in globals!";
		}
		
		var doSomething:Dynamic = engine.resolveField(myLibClass, "doSomething");
		if (doSomething == null) {
			throw "Failed to resolve doSomething static method!";
		}
		
		var result:String = doSomething();
		trace("MyLib.doSomething() result: " + result);
		
		if (result == "Hello from MyLib!") {
			trace("SUCCESS: Library bytecode bundle loaded and executed successfully from host!");
		} else {
			throw "Verification failed: MyLib.doSomething() returned: " + result;
		}
	}
}
