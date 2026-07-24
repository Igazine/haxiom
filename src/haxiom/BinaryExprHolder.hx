package haxiom;

import haxe.io.Bytes;

@:keep
@:allow(haxiom)
class BinaryExprHolder {
	private var bytes:Bytes;

	private function new(bytes:Bytes) {
		this.bytes = bytes;
	}
}
