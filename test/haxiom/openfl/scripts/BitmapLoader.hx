package;

import openfl.Assets;
import openfl.display.Bitmap;

class BitmapLoader {
	public static function main() {
		var bitmapData = Assets.getBitmapData("assets/openfl.png");
		var bitmap = new Bitmap(bitmapData);
		ScriptContext.container.addChild(bitmap);
	}
}

#if !haxiom
/*
 * Definitions for error-free local compilation, and Language Server Protocol in IDEs
 * This block is ignored in Haxiom
 */
class ScriptContext {
	public static var container:Dynamic;
}
#end
