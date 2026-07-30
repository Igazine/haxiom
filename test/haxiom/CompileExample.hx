package haxiom;

import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

class MockEvent {
	public var type:String = "trigger";
	public function new() {}
}

class MockButton {
	public var label:String;
	public var listeners:Array<Dynamic->Void> = [];
	public function new(label:String = null) {
		this.label = label;
	}
	public function addEventListener(type:String, listener:Dynamic->Void) {
		trace("MockButton.addEventListener: " + type + ", listener: " + listener);
		listeners.push(listener);
	}
	public function trigger() {
		trace("MockButton.trigger, listeners count: " + listeners.length);
		for (l in listeners) {
			l(new MockEvent());
		}
	}
}

class CompileExample {
	public static function main() {
		var script = "
            import feathers.controls.Button;
            import haxiom.MockEvent;
            using StringTools;
            var text = '     Click me!      '.trim();
            var btn = new Button(text);
            trace('Button label inside guest: ' + btn.label);
            btn.addEventListener('trigger', function(e:MockEvent) {
                trace('Callback invoked inside guest! event=' + e);
            });
            btn.trigger();
        ";
		var engine = new Haxiom();
		engine.useVM = true;
		engine.registerClass("feathers.controls.Button", MockButton);
		engine.registerClass("haxiom.MockEvent", MockEvent);

		// Compile without key (unencrypted)
		var bytes1 = engine.compileToBytecodeBytes(script, new ScriptContext("example1", "example1.hx"), null, false);
		trace("Saved example1.hxbc (" + bytes1.length + " bytes)");
		engine.executeBytes(bytes1);

		// Compile with 'this_is_my_secret' key (encrypted)
		var key = new HXBCKey("this_is_my_secret");
		var bytes2 = engine.compileToBytecodeBytes(script, new ScriptContext("example2", "example2.hx"), key, false);
		trace("Saved example2.hxbc (" + bytes2.length + " bytes)");

		var tempDir = "test/haxiom/tmp_compile_example_" + Std.int(haxe.Timer.stamp() * 1000000) + "_" + Std.random(1000000);
		deleteDirRecursive(tempDir);
		FileSystem.createDirectory(tempDir);
		try {
			var content = File.getBytes('./test/haxiom/openfl/scripts/Bytecode.hx');
			var bytes3 = engine.compileToBytecodeBytes(content.toString(), null, null, false);
			var bytecodePath = tempDir + "/Bytecode.hxbc";
			File.saveBytes(bytecodePath, bytes3);
			trace("Saved " + bytecodePath + " (" + bytes3.length + " bytes)");
			deleteDirRecursive(tempDir);
		} catch (e:Dynamic) {
			deleteDirRecursive(tempDir);
			throw e;
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
