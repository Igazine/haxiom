package haxiom;

class TestRuntimeStaticState {
	public static function runTests():Void {
		#if sys
		var violations = [];
		scanDirectory("src/haxiom", violations);
		if (violations.length > 0) {
			throw "Runtime static state violations:\n" + violations.join("\n");
		}
		trace("SUCCESS: Runtime static state scan passed.");
		#else
		trace("SKIPPED: Runtime static state scan requires sys filesystem access.");
		#end
	}

	#if sys
	static function scanDirectory(path:String, violations:Array<String>):Void {
		if (path == "src/haxiom/macro") {
			return;
		}
		for (entry in sys.FileSystem.readDirectory(path)) {
			var child = path + "/" + entry;
			if (sys.FileSystem.isDirectory(child)) {
				scanDirectory(child, violations);
			} else if (StringTools.endsWith(child, ".hx")) {
				scanFile(child, violations);
			}
		}
	}

	static function scanFile(path:String, violations:Array<String>):Void {
		var lines = sys.io.File.getContent(path).split("\n");
		for (i in 0...lines.length) {
			var line = StringTools.trim(lines[i]);
			if (line.length == 0 || StringTools.startsWith(line, "//")) {
				continue;
			}
			if (isStaticFieldDeclaration(line)) {
				violations.push(path + ":" + (i + 1) + ": " + line);
			}
		}
	}

	static function isStaticFieldDeclaration(line:String):Bool {
		line = stripStringLiterals(line);
		if (!~/\bstatic\b/.match(line) || ~/\bfunction\b/.match(line)) {
			return false;
		}
		return ~/^(@:[^\s]+\s+)*(public\s+|private\s+|static\s+|inline\s+|extern\s+|dynamic\s+)*(var|final)\b/.match(line);
	}

	static function stripStringLiterals(line:String):String {
		var out = new StringBuf();
		var quote = 0;
		var escaped = false;
		for (i in 0...line.length) {
			var code = line.charCodeAt(i);
			if (quote != 0) {
				if (escaped) {
					escaped = false;
				} else if (code == "\\".code) {
					escaped = true;
				} else if (code == quote) {
					quote = 0;
				}
				out.add(" ");
			} else if (code == "'".code || code == '"'.code) {
				quote = code;
				out.add(" ");
			} else {
				out.addChar(code);
			}
		}
		return out.toString();
	}
	#end
}
