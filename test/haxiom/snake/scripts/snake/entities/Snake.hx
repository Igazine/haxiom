package snake.entities;

class Snake {
    public var segments:Array<Dynamic>;
    public var direction:Int;

    public function new() {
        reset();
    }

    public function reset() {
        direction = 1; // Right
        segments = [
            {x: 15, y: 15},
            {x: 14, y: 15},
            {x: 13, y: 15}
        ];
    }

    public function getNextHead():Dynamic {
        var head = segments[0];
        if (head == null) return null;
        var nx = head.x;
        var ny = head.y;

        if (direction == 0) ny -= 1;
        else if (direction == 1) nx += 1;
        else if (direction == 2) ny += 1;
        else if (direction == 3) nx -= 1;

        return {x: nx, y: ny};
    }

    public function checkWallCollision(nx:Int, ny:Int):Bool {
        return (nx < 0 || nx >= 30 || ny < 0 || ny >= 30);
    }

    public function checkSelfCollision(nx:Int, ny:Int):Bool {
        for (seg in segments) {
            if (seg.x == nx && seg.y == ny) {
                return true;
            }
        }
        return false;
    }

    public function moveForward(nx:Int, ny:Int, eaten:Bool) {
        var newHead = {x: nx, y: ny};
        segments.unshift(newHead);
        if (!eaten) {
            segments.pop();
        }
    }
}
