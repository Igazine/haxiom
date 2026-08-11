package scenario.initializers;

class StaticInitializerImportSandbox {
	static var invalid:String = Sys.getCwd();

	static public function main():String {
		return invalid;
	}
}
