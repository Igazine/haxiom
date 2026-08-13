package interfaces;

interface IPlugin extends IPluginIdentity {
	var counter(get, set):Int;
	function doSomething():Void;
	function calc(a:Int, b:Int):Int;
}

interface IPluginIdentity {
	var pluginName(get, never):String;
}
