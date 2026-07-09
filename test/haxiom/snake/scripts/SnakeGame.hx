#if !haxiom_script
import openfl.display.Sprite;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.ui.Keyboard;
import openfl.text.TextField;
import openfl.text.TextFormat;

class ScriptContext {
    public static var gameRoot:Sprite;
}
class Timer {
    public static function delay(ms:Int):Dynamic return null;
}
#end

import snake.entities.Snake;
import snake.entities.Food;
import snake.utils.EffectManager;

class SnakeGame {
    var state:String; // "Menu", "Playing", "GameOver"
    var score:Int;
    var speedDelay:Int;
    
    var snakeObj:Snake;
    var foodObj:Food;
    
    var root:Sprite;
    var canvas:Sprite;
    var scoreLabel:TextField;
    var menuOverlay:Sprite;
    var menuText:TextField;
    
    public static function main() {
        var game = new SnakeGame();
        game.start();
    }
    
    public function new() {
        state = "Menu";
        score = 0;
        speedDelay = 150;
        
        snakeObj = new Snake();
        foodObj = new Food();
        
        root = ScriptContext.gameRoot;
    }
    
    public function start() {
        trace("SnakeGame starting...");
        // Create canvas
        canvas = new Sprite();
        root.addChild(canvas);
        
        // Create score text field
        var tf = new TextFormat();
        tf.size = 24;
        tf.color = 0xFFFFFF;
        
        scoreLabel = new TextField();
        scoreLabel.defaultTextFormat = tf;
        scoreLabel.x = 10;
        scoreLabel.y = 10;
        scoreLabel.width = 200;
        scoreLabel.height = 40;
        scoreLabel.selectable = false;
        scoreLabel.text = "Score: 0";
        root.addChild(scoreLabel);
        
        // Create menu overlay container
        menuOverlay = new Sprite();
        root.addChild(menuOverlay);
        
        menuText = new TextField();
        var menuTf = new TextFormat();
        menuTf.size = 24;
        menuTf.color = 0x00FF00;
        menuText.defaultTextFormat = menuTf;
        menuText.x = 80;
        menuText.y = 230;
        menuText.width = 440;
        menuText.height = 150;
        menuText.selectable = false;
        menuText.text = "HAXIOM SNAKE\nControl with WASD or Arrows\nClick anywhere to start!";
        menuOverlay.addChild(menuText);
        
        // Listen to click on stage/gameRoot to start/restart
        menuOverlay.addEventListener(MouseEvent.CLICK, onClickMenu);
        
        // Listen to keyboard inputs on root container
        root.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        
        // Initial drawing of background/board
        draw();
        
        // Start infinite VM tick loop
        tickLoop();
    }
    
    function tickLoop() {
        while (true) {
            if (state == "Playing") {
                update();
                draw();
            }
            Haxiom.await(Timer.delay(speedDelay)); // Dynamic speed delay
        }
    }
    
    function onClickMenu(e:MouseEvent) {
        if (state == "Menu" || state == "GameOver") {
            resetGame();
            state = "Playing";
            menuOverlay.visible = false;
            trace("Game started");
        }
    }
    
    function resetGame() {
        score = 0;
        scoreLabel.text = "Score: 0";
        speedDelay = 150;
        
        snakeObj.reset();
        foodObj.spawn(snakeObj.segments);
    }
    
    function onKeyDown(e:KeyboardEvent) {
        if (state != "Playing") return;
        
        var key = e.keyCode;
        if (key == Keyboard.UP || key == 87) { // Up or W
            if (snakeObj.direction != 2) snakeObj.direction = 0;
        } else if (key == Keyboard.RIGHT || key == 68) { // Right or D
            if (snakeObj.direction != 3) snakeObj.direction = 1;
        } else if (key == Keyboard.DOWN || key == 83) { // Down or S
            if (snakeObj.direction != 0) snakeObj.direction = 2;
        } else if (key == Keyboard.LEFT || key == 65) { // Left or A
            if (snakeObj.direction != 1) snakeObj.direction = 3;
        }
    }
    
    function update() {
        var nextHead = snakeObj.getNextHead();
        if (nextHead == null) return;
        
        // Wall collision
        if (snakeObj.checkWallCollision(nextHead.x, nextHead.y)) {
            triggerGameOver();
            return;
        }
        
        // Self collision
        if (snakeObj.checkSelfCollision(nextHead.x, nextHead.y)) {
            triggerGameOver();
            return;
        }
        
        // Check if food eaten
        var eaten = (nextHead.x == foodObj.x && nextHead.y == foodObj.y);
        
        snakeObj.moveForward(nextHead.x, nextHead.y, eaten);
        
        if (eaten) {
            score += 10;
            scoreLabel.text = "Score: " + score;
            
            // Trigger visual bite effect at the food location (hosted on the parent canvas)
            EffectManager.playBiteEffect(canvas, foodObj.x, foodObj.y);
            
            foodObj.spawn(snakeObj.segments);
            speedDelay = Std.int(Math.max(50, speedDelay - 5));
            trace("Food eaten! Speed delay: " + speedDelay + "ms");
        }
    }
    
    function triggerGameOver() {
        state = "GameOver";
        menuText.text = "GAME OVER\nScore: " + score + "\nClick anywhere to restart";
        menuOverlay.visible = true;
        trace("Game Over. Final Score: " + score);
    }
    
    function draw() {
        var g = canvas.graphics;
        g.clear();
        
        // Draw board background (600x600 area starting at y=50)
        g.beginFill(0x181818);
        g.drawRect(0, 50, 600, 600);
        g.endFill();
        
        // Draw grid border line
        g.lineStyle(2, 0x444444);
        g.drawRect(0, 50, 600, 600);
        g.lineStyle(0, 0); // Reset line style
        
        // Draw food (red block)
        g.beginFill(0xFF0000);
        g.drawRect(foodObj.x * 20, 50 + foodObj.y * 20, 20, 20);
        g.endFill();
        
        // Draw snake (green blocks, with neon green for head)
        for (i in 0...snakeObj.segments.length) {
            var seg = snakeObj.segments[i];
            if (i == 0) {
                g.beginFill(0x00FF00); // Head
            } else {
                g.beginFill(0x008800); // Body
            }
            g.drawRect(seg.x * 20 + 1, 50 + seg.y * 20 + 1, 18, 18);
            g.endFill();
        }
        
        // Draw Menu Overlay semi-transparent background if active
        if (state == "Menu" || state == "GameOver") {
            var og = menuOverlay.graphics;
            og.clear();
            og.beginFill(0x000000, 0.7);
            og.drawRect(0, 50, 600, 600);
            og.endFill();
        }
    }
}
