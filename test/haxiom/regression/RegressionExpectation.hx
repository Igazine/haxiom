package haxiom.regression;

enum RegressionExpectation {
	Value(expected:String);
	CompileFailure(messagePart:String);
	RuntimeFailure(messagePart:String);
}
