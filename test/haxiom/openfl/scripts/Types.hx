package scripts;

/**
	Testing type safety. All should fail at compile time.
**/
class Types {
	static public function main() {
		var failArray:Array<Int> = [1];
		failArray.push("100"); // Should fail at compile time

		var failList:List<String> = new List();
		failList.add(5); // Should fail at compile time

		var failMap:Map<Int, String> = new Map();
		failMap.set("hello", 5); // Should fail at compile time

		var failType:MyType<String, Int> = {key: 5, value: 5}; // Should fail at compile time

		var failEnum:MyEnum<Int> = MyEnum.Fail("hello"); // Should fail at compile time

		var failClass:MyClass<Int> = new MyClass("hello"); // Should fail at compile time
	}
}

typedef MyType<A, B> = {
	key:A,
	value:B,
}

enum MyEnum<T> {
	Ok;
	Fail(value:T);
}

class MyClass<T> {
	var value:Null<T>;

	public function new(?initValue:T) {
		value = initValue;
	}
}
