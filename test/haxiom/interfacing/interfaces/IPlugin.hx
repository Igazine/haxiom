package interfaces;

interface IPlugin extends IPluginIdentity {
	var counter(get, set):Int;
	function doSomething():Void;
	function calc(a:Int, b:Int):Int;
	function mutateBytes(value:haxe.io.Bytes):haxe.io.Bytes;
	function mutateNumbers(values:Array<Int>):Array<Int>;
	function updatePayload(payload:{name:String, count:Int}):{name:String, count:Int};
	function leakGuestValue():Dynamic;
}

interface IPluginIdentity {
	var pluginName(get, never):String;
}
