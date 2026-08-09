package haxiom.regression;

typedef RegressionSample = {
	var name:String;
	var moduleName:String;
	var source:String;
	var expected:RegressionExpectation;
	@:optional var staticTypes:Bool;
	@:optional var debugBytecode:Bool;
	@:optional var expectedLine:Int;
}
