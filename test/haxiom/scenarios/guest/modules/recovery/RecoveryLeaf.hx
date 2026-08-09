package scenario.modules.recovery;

class RecoveryLeaf {
	static var value:Int = 40;

	public static function nextValue():Int {
		return ++value;
	}
}
