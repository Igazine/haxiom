package snake.entities;

class Snake {
	public var segments:Array<{x:Int, y:Int}>;
	public var direction:Int; // 0: Up, 1: Right, 2: Down, 3: Left

	public function new() {
		reset();
	}

	public function reset() {
		segments = [{x: 10, y: 10}, {x: 10, y: 11}, {x: 10, y: 12}];
		direction = 0; // Up
	}

	public function getNextHead():{x:Int, y:Int} {
		if (segments.length == 0)
			return null;
		var head = segments[0];
		var nx = head.x;
		var ny = head.y;

		if (direction == 0)
			ny--;
		else if (direction == 1)
			nx++;
		else if (direction == 2)
			ny++;
		else if (direction == 3)
			nx--;

		return {x: nx, y: ny};
	}

	public function checkWallCollision(nx:Int, ny:Int):Bool {
		return (nx < 0 || nx >= 24 || ny < 0 || ny >= 20);
	}

	public function checkSelfCollision(nx:Int, ny:Int):Bool {
		// Ignore tail if it will move forward (handled separately in update)
		for (i in 0...(segments.length - 1)) {
			if (segments[i].x == nx && segments[i].y == ny) {
				return true;
			}
		}
		return false;
	}

	public function moveForward(nx:Int, ny:Int, eaten:Bool) {
		segments.unshift({x: nx, y: ny});
		if (!eaten) {
			segments.pop();
		}
	}
}
