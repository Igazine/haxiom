package haxiom;

/** Validates Haxe serialization structure before it can allocate runtime objects. */
@:allow(haxiom)
class HXBCConstantGuard {
	var source:String;
	var position:Int = 0;
	var maxValues:Int;
	var values:Int = 0;
	var strings:Array<String> = [];
	var resolver:HXBCTypeResolver;

	function new(source:String) {
		this.source = source;
		this.maxValues = source.length;
		this.resolver = new HXBCTypeResolver();
	}

	static function validate(source:String, maxBytes:Int):Void {
		if (source == null)
			throw "Invalid bytecode: null constant payload";
		if (maxBytes > 0 && source.length > maxBytes)
			throw "Invalid bytecode: constant payload exceeds limit";
		var guard = new HXBCConstantGuard(source);
		guard.readValue(0);
		if (guard.position != source.length)
			throw "Invalid bytecode: trailing constant payload data";
	}

	function readValue(depth:Int):Null<String> {
		if (depth > 256)
			throw "Invalid bytecode: constant payload nesting exceeds limit";
		if (position >= source.length)
			throw "Invalid bytecode: truncated constant payload";
		if (++values > maxValues)
			throw "Invalid bytecode: constant payload value count exceeds limit";

		var tag = source.charAt(position++);
		return switch (tag) {
			case "n", "t", "f", "z", "k", "m", "p": null;
			case "i":
				readInteger();
				null;
			case "d", "v":
				readFloat();
				null;
			case "y": readString();
			case "R":
				var index = readInteger();
				if (index < 0 || index >= strings.length)
					throw "Invalid bytecode: constant string reference out of bounds";
				strings[index];
			case "r":
				readInteger();
				null;
			case "s":
				readSizedData("bytes");
				null;
			case "x":
				readValue(depth + 1);
				null;
			case "a":
				while (!consume("h")) {
					if (consume("u")) {
						var count = readInteger();
						if (count <= 0 || count > source.length || values > maxValues - count)
							throw "Invalid bytecode: constant array null run exceeds limit";
						values += count;
					} else {
						readValue(depth + 1);
					}
				}
				null;
			case "l":
				while (!consume("h"))
					readValue(depth + 1);
				null;
			case "o":
				readFields(depth);
				null;
			case "b", "M":
				while (!consume("h")) {
					readValue(depth + 1);
					readValue(depth + 1);
				}
				null;
			case "q":
				while (!consume("h")) {
					expect(":");
					readInteger();
					readValue(depth + 1);
				}
				null;
			case "c":
				var name = readValue(depth + 1);
				if (name == null || resolver.resolveClass(name) == null)
					throw 'Invalid bytecode: constant class "$name" is not allowed';
				readFields(depth);
				null;
			case "C":
				throw "Invalid bytecode: custom constant deserialization is not allowed";
			case "w", "j":
				var name = readValue(depth + 1);
				if (name == null || resolver.resolveEnum(name) == null)
					throw 'Invalid bytecode: constant enum "$name" is not allowed';
				if (tag == "w")
					readValue(depth + 1);
				else {
					expect(":");
					readInteger();
				}
				expect(":");
				var count = readInteger();
				if (count < 0 || count > maxValues)
					throw "Invalid bytecode: constant enum argument count exceeds limit";
				for (_ in 0...count)
					readValue(depth + 1);
				null;
			case "A", "B":
				throw "Invalid bytecode: runtime type constants are not allowed";
			default:
				throw 'Invalid bytecode: unsupported constant serialization marker "$tag"';
		};
	}

	function readFields(depth:Int):Void {
		while (!consume("g")) {
			var field = readValue(depth + 1);
			if (field == null)
				throw "Invalid bytecode: constant object field name is not a string";
			readValue(depth + 1);
		}
	}

	function readString():String {
		var length = readInteger();
		if (length < 0)
			throw "Invalid bytecode: negative constant string length";
		expect(":");
		if (length > source.length - position)
			throw "Invalid bytecode: truncated constant string";
		var encoded = source.substr(position, length);
		position += length;
		var value = StringTools.urlDecode(encoded);
		strings.push(value);
		return value;
	}

	function readSizedData(label:String):Void {
		var length = readInteger();
		if (length < 0)
			throw 'Invalid bytecode: negative constant $label length';
		expect(":");
		if (length > source.length - position)
			throw 'Invalid bytecode: truncated constant $label';
		position += length;
	}

	function readInteger():Int {
		var start = position;
		if (position < source.length && source.charAt(position) == "-")
			position++;
		var digitStart = position;
		while (position < source.length) {
			var code = source.charCodeAt(position);
			if (code < 48 || code > 57)
				break;
			position++;
		}
		if (position == digitStart)
			throw "Invalid bytecode: malformed constant integer";
		var value = Std.parseInt(source.substring(start, position));
		if (value == null)
			throw "Invalid bytecode: constant integer overflow";
		return value;
	}

	function readFloat():Void {
		var start = position;
		while (position < source.length) {
			var c = source.charAt(position);
			if ((c >= "0" && c <= "9") || c == "+" || c == "-" || c == "." || c == "," || c == "e" || c == "E")
				position++;
			else
				break;
		}
		if (position == start || Math.isNaN(Std.parseFloat(source.substring(start, position))))
			throw "Invalid bytecode: malformed constant float";
	}

	inline function consume(value:String):Bool {
		if (position < source.length && source.charAt(position) == value) {
			position++;
			return true;
		}
		return false;
	}

	function expect(value:String):Void {
		if (!consume(value))
			throw 'Invalid bytecode: expected "$value" in constant payload';
	}
}
