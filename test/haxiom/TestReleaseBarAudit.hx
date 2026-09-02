package haxiom;

class TestReleaseBarAudit {
	public static function runTests():Void {
		#if sys
		var path = "test/haxiom/TestHaxiom.hx";
		var lines = sys.io.File.getContent(path).split("\n");
		var violations = [];

		for (i in 0...lines.length) {
			var trimmed = StringTools.trim(lines[i]);
			if (!StringTools.startsWith(trimmed, "//")) {
				continue;
			}
			var uncommented = StringTools.trim(trimmed.substr(2));
			if (StringTools.startsWith(uncommented, "haxiom.interpret(script") || uncommented == "InternalTests.run(haxiom);") {
				violations.push(path + ":" + (i + 1) + ": commented-out release-bar test call: " + uncommented);
			}
		}

		requireActiveCall(lines, path, "haxiom.interpret(script66);", 1, violations);
		requireActiveCall(lines, path, "haxiom.interpret(script68);", 3, violations);
		requireActiveCall(lines, path, "InternalTests.run(haxiom);", 1, violations);

		rejectPublicMembers("src/haxiom/Interp.hx", [
			"public var state(",
			"public function assertHostInterfaceIdentityAvailable("
		], violations);
		rejectPublicMembers("src/haxiom/MacroExpander.hx", [
			"public static function registerMacros(",
			"public static function expand("
		], violations);
		rejectPublicMembers("src/haxiom/LZ4.hx", [
			"public static function compress(",
			"public static function decompress("
		], violations);
		rejectPublicMembers("src/haxiom/ProxyBoundary.hx", [
			"public static function convert("
		], violations);
		rejectPublicMembers("src/haxiom/macro/ProxyGenerator.hx", [
			"public static function generateProxy("
		], violations);
		rejectPublicMembers("src/haxiom/ProxyBoundaryType.hx", [
			"public final kind:",
			"public final nullable:",
			"public final element:",
			"public final fields:",
			"public final name:",
			"public final type:",
			"public final optional:",
			"public function new("
		], violations);
		rejectPublicMembers("src/haxiom/Haxiom.hx", [
			"public function invokeProxyMethod(",
			"public function readProxyField(",
			"public function writeProxyField(",
			"public static function registerInterface(",
			"public static function constructHelper("
		], violations);
		rejectPublicMembers("src/haxiom/HaxiomTypes.hx", [
			"public var ",
			"public function new("
		], violations);

		if (violations.length > 0) {
			throw "Release-bar audit failed:\n" + violations.join("\n");
		}
		trace("SUCCESS: Release-bar source audit passed.");
		#else
		trace("SKIPPED: Release-bar source audit requires sys filesystem access.");
		#end
	}

	#if sys
	static function requireActiveCall(lines:Array<String>, path:String, call:String, minCount:Int, violations:Array<String>):Void {
		var count = 0;
		for (line in lines) {
			var trimmed = StringTools.trim(line);
			if (trimmed == call) {
				count++;
			}
		}
		if (count < minCount) {
			violations.push(path + ": expected at least " + minCount + " active `" + call + "` call(s), found " + count);
		}
	}

	static function rejectPublicMembers(path:String, signatures:Array<String>, violations:Array<String>):Void {
		var lines = sys.io.File.getContent(path).split("\n");
		for (i in 0...lines.length) {
			var trimmed = StringTools.trim(lines[i]);
			for (signature in signatures) {
				if (StringTools.startsWith(trimmed, signature)) {
					violations.push(path + ":" + (i + 1) + ": internal member is public: " + signature);
				}
			}
		}
	}
	#end
}
