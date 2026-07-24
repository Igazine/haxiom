package;

import TestOpenFL.ScriptDef;
import feathers.controls.TextArea;
import feathers.text.TextFormat;
import haxe.io.Bytes;
import openfl.events.Event;
import openfl.net.URLLoader;
import openfl.net.URLLoaderDataFormat;
import openfl.net.URLRequest;

class ScriptArea extends TextArea {
	var _currentScriptContent:Bytes;

	public var currentScript(default, null):ScriptDef;
	public var currentScriptContent(get, null):Bytes;

	function get_currentScriptContent():Bytes {
		if (currentScript != null && currentScript.isBytecode) {
			return _currentScriptContent;
		}
		return Bytes.ofString(this.text);
	}

	public function new() {
		super();
		this.textFormat = new TextFormat('_typewriter', 14, 0xCCCCCC);
	}

	public function load(script:ScriptDef) {
		currentScript = script;
		var request:URLRequest = new URLRequest(script.path);
		var loader = new URLLoader();
		loader.dataFormat = URLLoaderDataFormat.BINARY;
		loader.addEventListener(Event.COMPLETE, (event) -> {
			_currentScriptContent = cast event.target.data;
			trace('Successfully loaded ${script.id} (${_currentScriptContent.length} bytes)');
			if (currentScript.isBytecode) {
				if (currentScript.inspect == true) {
					var info = haxiom.Haxiom.inspectBytecode(_currentScriptContent);
					this.text = formatInspection(info);
				} else {
					this.text = "Pre-compiled bytecode loaded (size: " + Std.string(_currentScriptContent.length) + " bytes)";
				}
				this.editable = false;
			} else {
				this.text = _currentScriptContent.toString();
				this.editable = true;
			}
		});
		loader.load(request);
	}

	function formatInspection(info:haxiom.Haxiom.HXBCInfo):String {
		var buf = new StringBuf();
		buf.add("=== HXBC BYTECODE INSPECTION OBJECT ===\n\n");
		buf.add("Status:                   " + info.status + "\n");
		buf.add("File Size:                " + info.fileSize + " bytes\n");
		buf.add("Uncompressed Size:        " + info.uncompressedPayloadSize + " bytes\n");
		buf.add("Compression Ratio:        " + info.compressionRatioPct + "%\n");
		buf.add("Format Version:           v" + info.version + "\n");
		buf.add("Max Fiber Slots:          " + info.maxSlots + "\n");
		buf.add("Async Mode:               " + info.isAsync + "\n");
		buf.add("Encrypted:                " + info.isEncrypted + "\n");
		buf.add("Compressed:               " + info.isCompressed + "\n");
		buf.add("Checksum:                 " + info.checksum + "\n");

		if (info.error != null) {
			buf.add("\nError:                    " + info.error + "\n");
		}

		if (info.instructionCount != null) {
			buf.add("\n--- PAYLOAD METADATA ---\n");
			buf.add("Instruction Count:        " + info.instructionCount + "\n");
			buf.add("Constant Pool Size:       " + info.constantPoolSize + "\n");
			buf.add("Debug Symbols:            " + info.debugSymbolCount + "\n");
			buf.add("Position Mappings:        " + info.positionMappingCount + "\n");
		}

		if (info.sourceFiles != null && info.sourceFiles.length > 0) {
			buf.add("\n--- SOURCE FILES ---\n");
			for (f in info.sourceFiles) {
				buf.add("- " + f + "\n");
			}
		}

		if (info.compiledTypes != null && info.compiledTypes.length > 0) {
			buf.add("\n--- COMPILED TYPES ---\n");
			for (t in info.compiledTypes) {
				buf.add("- " + t.kind + ": " + t.name);
				if (t.parent != null) buf.add(" extends " + t.parent);
				buf.add("\n");
			}
		}

		if (info.debugSymbols != null && info.debugSymbols.length > 0) {
			buf.add("\n--- DEBUG SYMBOLS ---\n");
			for (s in info.debugSymbols) {
				buf.add("- slot " + s.slot + ": " + s.name + " (IP " + s.startIp + ".." + s.endIp + ")\n");
			}
		}

		return buf.toString();
	}
}
