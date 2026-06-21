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
				this.text = "Pre-compiled bytecode loaded (size: " + Std.string(_currentScriptContent.length) + " bytes)";
				this.editable = false;
			} else {
				this.text = _currentScriptContent.toString();
				this.editable = true;
			}
		});
		loader.load(request);
	}
}
