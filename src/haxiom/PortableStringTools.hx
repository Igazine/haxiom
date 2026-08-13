package haxiom;

@:allow(haxiom)
class PortableStringTools {
	static function trim(value:String):String {
		return sliceTrimmed(value, true, true);
	}

	static function ltrim(value:String):String {
		return sliceTrimmed(value, true, false);
	}

	static function rtrim(value:String):String {
		return sliceTrimmed(value, false, true);
	}

	static function sliceTrimmed(value:String, trimLeft:Bool, trimRight:Bool):String {
		var start = 0;
		var end = value.length;
		if (trimLeft) {
			while (start < end && isSpace(StringTools.fastCodeAt(value, start)))
				start++;
		}
		if (trimRight) {
			while (end > start && isSpace(StringTools.fastCodeAt(value, end - 1)))
				end--;
		}
		if (start == 0 && end == value.length)
			return value;
		var result = new StringBuf();
		for (i in start...end)
			result.addChar(StringTools.fastCodeAt(value, i));
		return result.toString();
	}

	static inline function isSpace(code:Int):Bool {
		return code == 32 || (code >= 9 && code <= 13);
	}
}
