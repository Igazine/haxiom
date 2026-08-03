package haxiom.scenarios;

typedef ScenarioDefinition = {
	var name:String;
	var moduleName:String;
	var source:String;
	var expected:String;
	@:optional var configure:Haxiom->Void;
	@:optional var vmOnly:Bool;
}
