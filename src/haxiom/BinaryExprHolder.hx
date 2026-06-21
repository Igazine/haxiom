package haxiom;

import haxe.io.Bytes;

@:keep
class BinaryExprHolder {
    public var bytes:Bytes;

    public function new(bytes:Bytes) {
        this.bytes = bytes;
    }
}
