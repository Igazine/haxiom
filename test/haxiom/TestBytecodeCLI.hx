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
			var bytecodeKey = "cli_obfuscation_key";
			File.saveContent(scriptPath, "
				class CliSmoke {
					public static function main():Int {
						var total = 0;
						for (i in 0...5) {
							total += i;
						}
						if (total != 10) throw 'bad total: ' + total;
						return total;
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
			assertExecutableBytecode(bytecodePath, bytecodeKey, 10);

			deleteDirRecursive(tempDir);
		} catch (e:Dynamic) {
			deleteDirRecursive(tempDir);
			throw e;
		}
		trace("ALL BYTECODE CLI TESTS PASSED!");
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

	static function assertExecutableBytecode(bytecodePath:String, key:String, expected:Int):Void {
		var haxiom = new Haxiom();
		haxiom.useVM = true;
		var result:Int = haxiom.executeBytecodeBytes(File.getBytes(bytecodePath), null, new HXBCKey(key));
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
