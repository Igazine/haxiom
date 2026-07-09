package snake.utils;

#if !haxiom_script
import openfl.display.Sprite;
import openfl.display.Shape;
import motion.Actuate;
#end

class EffectManager {
    public static function playBiteEffect(parent:Sprite, foodX:Int, foodY:Int) {
        var s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawCircle(0, 0, 10);
        s.graphics.endFill();
        
        s.x = foodX * 20 + 10;
        s.y = 50 + foodY * 20 + 10;
        parent.addChild(s);
        
        // Tween scale and alpha, then remove from display list on complete
        motion.Actuate.tween(s, 1.0, { scaleX: 3.0, scaleY: 3.0, alpha: 0.0 }).onComplete(function() {
            parent.removeChild(s);
        });
    }
}
