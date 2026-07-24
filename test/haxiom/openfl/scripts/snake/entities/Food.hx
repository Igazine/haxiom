package snake.entities;

class Food {
	public var x:Int;
	public var y:Int;

	public function new() {
		x = 5;
		y = 5;
	}

	public function spawn(snakeSegments:Array<{x:Int, y:Int}>) {
		var valid = false;
		while (!valid) {
			var rx = Std.int(Math.random() * 24);
			var ry = Std.int(Math.random() * 20);

			var overlap = false;
			for (seg in snakeSegments) {
				if (seg.x == rx && seg.y == ry) {
					overlap = true;
					break;
				}
			}

			if (!overlap) {
				x = rx;
				y = ry;
				valid = true;
			}
		}
	}
}
