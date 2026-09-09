package haxiom;

import haxe.Json;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class TestBytecodeCLI {
	static function main():Void {
		trace("Haxiom Bytecode CLI Verification Suite");
		trace("---------------------------------------");

		var tempDir = "test/haxiom/tmp_cli_" + Std.int(haxe.Timer.stamp() * 1000000) + "_" + Std.random(1000000);
		deleteDirRecursive(tempDir);
		FileSystem.createDirectory(tempDir);

		try {
			var scriptPath = tempDir + "/CliSmoke.hx";
			var bytecodePath = tempDir + "/CliSmoke.hxbc";
			var resourcePath = tempDir + "/payload.bin";
			var bytecodeKey = "cli_obfuscation_key";
			var resourceBytes = Bytes.alloc(6);
			var resourceValues = [0, 1, 127, 128, 254, 255];
			for (i in 0...resourceValues.length) {
				resourceBytes.set(i, resourceValues[i]);
			}
			File.saveBytes(resourcePath, resourceBytes);
			File.saveContent(scriptPath, "
				import haxe.io.Bytes;

				class CliSmoke {
					@:haxiom.resource(\"payload.bin\")
					static var payload:Bytes;

					public static function main():String {
						var total = 0;
						for (i in 0...5) {
							total += i;
						}
						if (total != 10) throw 'bad total: ' + total;
						return total + '|' + payload.length + '|' + payload.get(0) + '|' + payload.get(3) + '|' + payload.get(4) + '|' + payload.get(5);
					}
				}
			");

			runProcess(["run", "haxiom", "bc", scriptPath], "bytecode compile");
			assertExists(bytecodePath, "plain bytecode output");
			assertValidInspection(bytecodePath, false);

			FileSystem.deleteFile(bytecodePath);
			runProcess(["run", "haxiom", "bc", scriptPath, "-c"], "compressed bytecode compile");
			assertExists(bytecodePath, "compressed bytecode output");
			assertValidInspection(bytecodePath, true);

			FileSystem.deleteFile(bytecodePath);
			runProcess(["run", "haxiom", "bc", scriptPath, bytecodeKey, "-c"], "keyed compressed bytecode compile");
			assertExists(bytecodePath, "keyed compressed bytecode output");
			assertEncryptedInspection(bytecodePath, true);
			assertValidInspection(bytecodePath, true, bytecodeKey, true);
			assertEmbeddedResource(bytecodePath, bytecodeKey, "payload.bin", resourceBytes.length);
			assertExecutableBytecode(bytecodePath, bytecodeKey, "10|6|0|128|254|255");

			assertDebugCompilation(tempDir, bytecodeKey);

			var invalidPath = tempDir + "/InvalidRoot.hx";
			File.saveContent(invalidPath, "class InvalidRoot {}\ntrace('must not compile');");
			assertRejectedModule(invalidPath);
			File.saveContent(invalidPath, "import BadDependency; class InvalidRoot { static public function main():Int return BadDependency.value; }");
			File.saveContent(tempDir + "/BadDependency.hx", "class BadDependency { static public var value:Int = 1; }\ntrace('must not compile');");
			assertRejectedModule(invalidPath);

			File.saveContent(invalidPath, "class InvalidRoot { static var value = untyped 1; }");
			assertRejectedModule(invalidPath, "'untyped' keyword is not supported");
			File.saveContent(invalidPath, "import BadDependency; class InvalidRoot { static public function main():Int return BadDependency.value; }");
			File.saveContent(tempDir + "/BadDependency.hx", "class BadDependency { static public var value = untyped 1; }");
			assertRejectedModule(invalidPath, "'untyped' keyword is not supported");

			deleteDirRecursive(tempDir);
		} catch (e:Dynamic) {
			deleteDirRecursive(tempDir);
			throw e;
		}
		trace("ALL BYTECODE CLI TESTS PASSED!");
	}

	static function assertDebugCompilation(tempDir:String, key:String):Void {
		var dir = tempDir + "/debug";
		FileSystem.createDirectory(dir);
		var sourcePath = dir + "/DebugFailure.hx";
		var bytecodePath = dir + "/DebugFailure.hxbc";
		File.saveContent(sourcePath, "class DebugFailure {\n"
			+ "static public function main():Void {\n"
			+ "var diagnosticValue = 123;\n"
			+ "throw 'expected debug failure';\n}\n}");
		for (mode in 0...3) {
			var args = ["run", "haxiom", "bc", mode == 2 ? dir : sourcePath];
			if (mode > 0) args.push("--debug");
			if (mode == 2) {
				args.push(key);
				args.push("-c");
			}
			runProcess(args, "debug compilation mode " + mode);
			assertValidInspection(bytecodePath, mode == 2, mode == 2 ? key : null, mode == 2);
			var engine = new Haxiom();
			var caught = false;
			try {
				engine.executeBytecodeBytes(File.getBytes(bytecodePath), null, mode == 2 ? new HXBCKey(key) : null);
			} catch (e:ScriptException) {
				caught = true;
				if (e.rawValue != "expected debug failure") throw e;
				if (mode > 0) {
					if (e.locals == null || e.locals.get("diagnosticValue") != 123)
						throw "Debug CLI compilation lost the unused local variable";
					if (e.line != 4 || e.file == null || e.file.indexOf("DebugFailure.hx") == -1)
						throw 'Debug CLI compilation lost source location: ${e.file}:${e.line}';
				} else if (e.locals != null && e.locals.exists("diagnosticValue")) {
					throw "Release CLI compilation unexpectedly retained local debug symbols";
				}
			}
			if (!caught) throw "Debug fixture did not throw";
			FileSystem.deleteFile(bytecodePath);
		}
	}

	static function assertValidInspection(bytecodePath:String, expectedCompressed:Bool, ?key:String, expectedEncrypted:Bool = false):Void {
		var args = ["run", "haxiom", "inspect", bytecodePath];
		if (key != null) {
			args.push(key);
		}
		args.push("--json");
		var output = runProcess(args, "bytecode inspect json");
		var info:Dynamic = Json.parse(output);
		if (info.status != "VALID") {
			throw 'inspect status failed: ${info.status} ${info.error}';
		}
		if (info.filePath != bytecodePath) {
			throw 'inspect reported wrong filePath: ${info.filePath}';
		}
		if (info.version == null || info.version <= 0) {
			throw 'inspect reported invalid version: ${info.version}';
		}
		if (info.fileSize == null || info.fileSize <= 0) {
			throw 'inspect reported invalid file size: ${info.fileSize}';
		}
		if (info.instructionCount == null || info.instructionCount <= 0) {
			throw 'inspect reported invalid instruction count: ${info.instructionCount}';
		}
		if (info.isCompressed != expectedCompressed) {
			throw 'inspect compression mismatch: expected ${expectedCompressed}, got ${info.isCompressed}';
		}
		if (info.isEncrypted != expectedEncrypted) {
			throw 'inspect encryption mismatch: expected ${expectedEncrypted}, got ${info.isEncrypted}';
		}
	}

	static function assertEncryptedInspection(bytecodePath:String, expectedCompressed:Bool):Void {
		var output = runProcess(["run", "haxiom", "inspect", bytecodePath, "--json"], "encrypted bytecode inspect json without key");
		var info:Dynamic = Json.parse(output);
		if (info.status != "ENCRYPTED") {
			throw 'inspect should report ENCRYPTED without key, got ${info.status} ${info.error}';
		}
		if (info.isEncrypted != true) {
			throw 'inspect failed to report encrypted payload';
		}
		if (info.isCompressed != expectedCompressed) {
			throw 'inspect encrypted compression mismatch: expected ${expectedCompressed}, got ${info.isCompressed}';
		}
	}

	static function assertEmbeddedResource(bytecodePath:String, key:String, expectedPath:String, expectedSize:Int):Void {
		var output = runProcess(["run", "haxiom", "inspect", bytecodePath, key, "--json"], "embedded resource inspect json");
		var info:Dynamic = Json.parse(output);
		var found = false;
		if (info.embeddedResources != null) {
			for (resource in cast(info.embeddedResources, Array<Dynamic>)) {
				if (resource.path == expectedPath && resource.size == expectedSize) {
					found = true;
					break;
				}
			}
		}
		if (!found) {
			throw 'inspect did not report embedded resource ${expectedPath} (${expectedSize} bytes)';
		}
	}

	static function assertExecutableBytecode(bytecodePath:String, key:String, expected:String):Void {
		var haxiom = new Haxiom();
		haxiom.useVM = true;
		var result:String = haxiom.executeBytecodeBytes(File.getBytes(bytecodePath), null, new HXBCKey(key));
		if (result != expected) {
			throw 'keyed bytecode execution mismatch: expected ${expected}, got ${result}';
		}
	}

	static function assertExists(path:String, label:String):Void {
		if (!FileSystem.exists(path)) {
			throw '${label} was not created at ${path}';
		}
	}

	static function runProcess(args:Array<String>, label:String):String {
		var process = new Process("haxelib", args);
		var stdout = process.stdout.readAll().toString();
		var stderr = process.stderr.readAll().toString();
		var code = process.exitCode();
		process.close();
		if (code != 0) {
			throw '${label} failed with exit code ${code}\nSTDOUT:\n${stdout}\nSTDERR:\n${stderr}';
		}
		return stdout;
	}

	static function assertRejectedModule(path:String, expectedError:String = "Top-level executable code is not allowed"):Void {
		var process = new Process("haxelib", ["run", "haxiom", "bc", path, "-c"]);
		var stdout = process.stdout.readAll().toString();
		var stderr = process.stderr.readAll().toString();
		var code = process.exitCode();
		process.close();
		if (code == 0 || (stdout + stderr).indexOf(expectedError) == -1)
			throw 'CLI accepted invalid module or returned wrong error: $stdout $stderr';
		if (FileSystem.exists(haxe.io.Path.withoutExtension(path) + ".hxbc"))
			throw "CLI wrote bytecode for an invalid module";
	}

	static function deleteDirRecursive(path:String):Void {
		if (!FileSystem.exists(path)) {
			return;
		}
		for (entry in FileSystem.readDirectory(path)) {
			var child = path + "/" + entry;
			if (FileSystem.isDirectory(child)) {
				deleteDirRecursive(child);
			} else {
				FileSystem.deleteFile(child);
			}
		}
		FileSystem.deleteDirectory(path);
	}
}
