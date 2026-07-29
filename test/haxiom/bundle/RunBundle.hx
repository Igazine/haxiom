package haxiom.bundle;

import haxiom.Haxiom;
import haxiom.LibRun;
import sys.FileSystem;
import sys.io.File;

class RunBundle {
	public static function main() {
		var tempDir = "test/haxiom/tmp_bundle_" + Std.int(haxe.Timer.stamp() * 1000000) + "_" + Std.random(1000000);
		deleteDirRecursive(tempDir);
		copyDirectory("test/haxiom/bundle", tempDir);

		var engine = new Haxiom();
		engine.useVM = true;
		engine.importWhitelist = null; // Disable sandboxing for standard outputs

		try {
			trace("Compiling library test bundle bytecode...");
			LibRun.bytecodeCompile(tempDir + "/", "StupidLogic.hx");

			trace("Loading library test bundle bytecode...");
			var bytes = File.getBytes(tempDir + "/StupidLogic.hxbc");

			trace("Executing library test bundle...");
			engine.executeBytes(bytes);

			trace("Resolving StupidLogic output fields using engine APIs...");
			var logicClass:Dynamic = engine.getGlobal("StupidLogic");
			if (logicClass == null) {
				throw "StupidLogic class was not registered in globals!";
			}

			var outputMessage:String = engine.resolveField(logicClass, "outputMessage");
			var outputValue:Int = engine.resolveField(logicClass, "outputValue");
			trace("StupidLogic output: " + outputMessage + " / " + outputValue);

			if (outputMessage == "Hello from bundled MyClass!" && outputValue == 40) {
				trace("SUCCESS: Library bytecode bundle loaded and executed successfully from host!");
			} else {
				throw "Verification failed: StupidLogic returned: " + outputMessage + " / " + outputValue;
			}
			deleteDirRecursive(tempDir);
		} catch (e:Dynamic) {
			deleteDirRecursive(tempDir);
			throw e;
		}
	}

	static function copyDirectory(source:String, destination:String):Void {
		FileSystem.createDirectory(destination);
		for (entry in FileSystem.readDirectory(source)) {
			var sourcePath = source + "/" + entry;
			var destinationPath = destination + "/" + entry;
			if (FileSystem.isDirectory(sourcePath)) {
				copyDirectory(sourcePath, destinationPath);
			} else if (StringTools.endsWith(sourcePath, ".hx")) {
				File.copy(sourcePath, destinationPath);
			}
		}
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
