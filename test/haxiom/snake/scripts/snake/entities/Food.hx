package snake.entities;

class Food {
    public var x:Int;
    public var y:Int;

    public function new() {
        x = 5;
        y = 5;
    }

    public function spawn(snakeSegments:Array<Dynamic>) {
        var valid = false;
        var rx = 0;
        var ry = 0;
        while (!valid) {
            rx = Std.int(Math.random() * 30);
            ry = Std.int(Math.random() * 30);
            valid = true;
            for (seg in snakeSegments) {
                if (seg.x == rx && seg.y == ry) {
                    valid = false;
                    break;
                }
            }
        }
        x = rx;
        y = ry;
    }
}
