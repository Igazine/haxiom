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

class SnakeGame {
    var state:String; // "Menu", "Playing", "GameOver"
    var score:Int;
    var direction:Int; // 0=Up, 1=Right, 2=Down, 3=Left
    var snake:Array<Dynamic>; // Array of segments {x:Int, y:Int}
    var food:Dynamic; // {x:Int, y:Int}
    var speedDelay:Int; // Current tick delay in ms (decreases as snake eats)
    
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
        direction = 1;
        snake = [];
        food = {x: 5, y: 5};
        speedDelay = 150;
        
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
        direction = 1; // Right
        speedDelay = 150; // Initial delay (slow)
        
        // Start snake at center
        snake = [
            {x: 15, y: 15},
            {x: 14, y: 15},
            {x: 13, y: 15}
        ];
        
        spawnFood();
    }
    
    function spawnFood() {
        var valid = false;
        var rx = 0;
        var ry = 0;
        while (!valid) {
            rx = Std.int(Math.random() * 30);
            ry = Std.int(Math.random() * 30);
            valid = true;
            for (seg in snake) {
                if (seg.x == rx && seg.y == ry) {
                    valid = false;
                    break;
                }
            }
        }
        food = {x: rx, y: ry};
    }
    
    function onKeyDown(e:KeyboardEvent) {
        if (state != "Playing") return;
        
        var key = e.keyCode;
        if (key == Keyboard.UP || key == 87) { // Up or W
            if (direction != 2) direction = 0;
        } else if (key == Keyboard.RIGHT || key == 68) { // Right or D
            if (direction != 3) direction = 1;
        } else if (key == Keyboard.DOWN || key == 83) { // Down or S
            if (direction != 0) direction = 2;
        } else if (key == Keyboard.LEFT || key == 65) { // Left or A
            if (direction != 1) direction = 3;
        }
    }
    
    function update() {
        // Calculate new head position
        var head = snake[0];
        if (head == null) return;
        var nx = head.x;
        var ny = head.y;
        
        if (direction == 0) ny -= 1;
        else if (direction == 1) nx += 1;
        else if (direction == 2) ny += 1;
        else if (direction == 3) nx -= 1;
        
        // Collision checks: Wall
        if (nx < 0 || nx >= 30 || ny < 0 || ny >= 30) {
            triggerGameOver();
            return;
        }
        
        // Collision checks: Self
        for (seg in snake) {
            if (seg.x == nx && seg.y == ny) {
                triggerGameOver();
                return;
            }
        }
        
        // Move snake
        var newHead = {x: nx, y: ny};
        snake.unshift(newHead);
        
        // Check if food eaten
        if (nx == food.x && ny == food.y) {
            score += 10;
            scoreLabel.text = "Score: " + score;
            spawnFood();
            // Speed up: subtract 5ms delay (minimum cap at 50ms)
            speedDelay = Std.int(Math.max(50, speedDelay - 5));
            trace("Food eaten! Speed delay: " + speedDelay + "ms");
        } else {
            // Remove tail if didn't eat
            snake.pop();
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
        g.drawRect(food.x * 20, 50 + food.y * 20, 20, 20);
        g.endFill();
        
        // Draw snake (green blocks, with neon green for head)
        for (i in 0...snake.length) {
            var seg = snake[i];
            if (i == 0) {
                g.beginFill(0x00FF00); // Head
            } else {
                g.beginFill(0x008800); // Body
            }
            g.drawRect(seg.x * 20 + 1, 50 + seg.y * 20 + 1, 18, 18); // 1px gap between segments
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
