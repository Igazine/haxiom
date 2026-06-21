package;

import mypackage.sub.MyClass;
import other.Helper;

class StupidLogic {
	public static var outputMessage:String = "";
	public static var outputValue:Int = 0;

	public static function main() {
		outputMessage = MyClass.getMessage();
		outputValue = Helper.computeValue(4);
		trace(outputMessage + " Computed: " + outputValue);
	}
}
