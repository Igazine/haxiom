package;

import mypackage.sub.MyClass;
import other.Helper;

class MyLib {
	static public function doSomething():String {
		return "Hello from MyLib!";
	}
}

class Crypto {
	var num:Int = 0;

	public function new() {}

	public function increment() {
		num++;
	}
}

class Random {
	static public function main() {
		trace("Hello from Random!");
	}

	static public function get():Int {
		return 42;
	}
}
