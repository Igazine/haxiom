import openfl.display.Sprite;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.ui.Keyboard;
import snake.entities.Food;
import snake.entities.Snake;
import snake.utils.EffectManager;

extern class ScriptContext {
	public static var container:Dynamic;
	public static var gameRoot:Sprite;
}

extern class Timer {
	public static function delay(ms:Int):Dynamic;
}

class SnakeGame {
	var state:String; // "Menu", "Playing", "GameOver"
	var score:Int;
	var speedDelay:Int;
	var directionChangedThisTick:Bool;

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
		directionChangedThisTick = false;

		snakeObj = new Snake();
		foodObj = new Food();

		root = ScriptContext.container != null ? ScriptContext.container : ScriptContext.gameRoot;
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
		canvas.addChild(scoreLabel);

		// Create menu overlay container
		menuOverlay = new Sprite();
		canvas.addChild(menuOverlay);

		menuText = new TextField();
		var menuTf = new TextFormat();
		menuTf.size = 24;
		menuTf.color = 0x00FF00;
		menuText.defaultTextFormat = menuTf;
		menuText.x = 80;
		menuText.y = 180;
		menuText.width = 440;
		menuText.height = 150;
		menuText.selectable = false;
		menuText.text = "HAXIOM SNAKE\nControl with WASD or Arrows\nClick anywhere to start!";
		menuOverlay.addChild(menuText);

		// Listen to click on overlay or root canvas to start/restart
		menuOverlay.addEventListener(MouseEvent.CLICK, onClickMenu);
		canvas.addEventListener(MouseEvent.CLICK, onClickMenu);

		// Listen to keyboard inputs on root container and stage
		root.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		if (root.stage != null) {
			root.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		}

		// Reset and auto-start game
		resetGame();
		state = "Playing";
		menuOverlay.visible = false;

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
			HaxiomHost.await(Timer.delay(speedDelay)); // Dynamic speed delay
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
		directionChangedThisTick = false;

		snakeObj.reset();
		foodObj.spawn(snakeObj.segments);
	}

	function onKeyDown(e:KeyboardEvent) {
		if (state != "Playing" || directionChangedThisTick)
			return;

		var key = e.keyCode;
		var changed = false;
		if (key == Keyboard.UP || key == 87) { // Up or W
			if (snakeObj.direction != 2) {
				snakeObj.direction = 0;
				changed = true;
			}
		} else if (key == Keyboard.RIGHT || key == 68) { // Right or D
			if (snakeObj.direction != 3) {
				snakeObj.direction = 1;
				changed = true;
			}
		} else if (key == Keyboard.DOWN || key == 83) { // Down or S
			if (snakeObj.direction != 0) {
				snakeObj.direction = 2;
				changed = true;
			}
		} else if (key == Keyboard.LEFT || key == 65) { // Left or A
			if (snakeObj.direction != 1) {
				snakeObj.direction = 3;
				changed = true;
			}
		}
		if (changed) {
			directionChangedThisTick = true;
		}
	}

	function update() {
		directionChangedThisTick = false;

		var nextHead = snakeObj.getNextHead();
		if (nextHead == null)
			return;

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

		// Draw board background (500x450 area starting at y=40)
		g.beginFill(0x181818);
		g.drawRect(0, 40, 500, 450);
		g.endFill();

		// Draw grid border line
		g.lineStyle(2, 0x444444);
		g.drawRect(0, 40, 500, 450);
		g.lineStyle(0, 0); // Reset line style

		// Draw food (red block)
		g.beginFill(0xFF0000);
		g.drawRect(foodObj.x * 20, 40 + foodObj.y * 20, 20, 20);
		g.endFill();

		// Draw snake (green blocks, with neon green for head)
		for (i in 0...snakeObj.segments.length) {
			var seg = snakeObj.segments[i];
			if (i == 0) {
				g.beginFill(0x00FF00); // Head
			} else {
				g.beginFill(0x008800); // Body
			}
			g.drawRect(seg.x * 20 + 1, 40 + seg.y * 20 + 1, 18, 18);
			g.endFill();
		}

		// Draw Menu Overlay semi-transparent background if active
		if (state == "Menu" || state == "GameOver") {
			var og = menuOverlay.graphics;
			og.clear();
			og.beginFill(0x000000, 0.7);
			og.drawRect(0, 40, 500, 450);
			og.endFill();
		}
	}
}
