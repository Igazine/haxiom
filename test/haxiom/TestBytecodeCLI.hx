package haxiom;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class TestBytecodeCLI {
	static function main():Void {
		trace("Haxiom Bytecode CLI Verification Suite");
		trace("---------------------------------------");

		var tempDir = "test/haxiom/tmp_cli";
		deleteDirRecursive(tempDir);
		FileSystem.createDirectory(tempDir);

		try {
			var scriptPath = tempDir + "/CliSmoke.hx";
			var bytecodePath = tempDir + "/CliSmoke.hxbc";
			File.saveContent(scriptPath, "
				class CliSmoke {
					public static function main() {
						var total = 0;
						for (i in 0...5) {
							total += i;
						}
						if (total != 10) throw 'bad total: ' + total;
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

			deleteDirRecursive(tempDir);
		} catch (e:Dynamic) {
			deleteDirRecursive(tempDir);
			throw e;
		}
		trace("ALL BYTECODE CLI TESTS PASSED!");
	}

	static function assertValidInspection(bytecodePath:String, expectedCompressed:Bool):Void {
		var output = runProcess(["run", "haxiom", "inspect", bytecodePath, "--json"], "bytecode inspect json");
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
