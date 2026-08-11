package scenario.initializers;

class StaticInitializerFieldSandbox {
	static var invalid:String = hostSecret.value;

	static public function main():String {
		return invalid;
	}
}
