package snake.utils;

import openfl.display.Sprite;

class EffectManager {
	public static function playBiteEffect(parentCanvas:Sprite, gridX:Int, gridY:Int) {
		var biteEffect = new Sprite();
		var eg = biteEffect.graphics;
		eg.lineStyle(2, 0xFFFF00);
		eg.drawCircle(gridX * 20 + 10, 40 + gridY * 20 + 10, 15);
		parentCanvas.addChild(biteEffect);

		// Fade out effect using static extension / helper
		haxe.Timer.delay(function() {
			if (biteEffect.parent != null) {
				biteEffect.parent.removeChild(biteEffect);
			}
		}, 150);
	}
}
