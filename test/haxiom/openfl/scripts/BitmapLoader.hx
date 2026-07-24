package;

import openfl.display.Bitmap;
import openfl.display.BitmapData;

class BitmapLoader {
	@:haxiom.resource("../assets/openfl.png")
	static var logoBytes:haxe.io.Bytes;

	public static function main() {
		if (logoBytes != null) {
			var bitmapData = BitmapData.loadFromBytes(logoBytes).onComplete(function(b) {
				var bitmap = new Bitmap(b);
				ScriptContext.container.addChild(bitmap);
			});
		}
	}
}

extern class ScriptContext {
	public static var container:Dynamic;
}
