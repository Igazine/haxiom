package host;

import haxiom.*;
import interfaces.IPlugin;

class Host {
	static function resource(name:String):String {
		var source = haxe.Resource.getString(name);
		if (source == null)
			throw 'Missing embedded test resource: $name';
		return source;
	}

	static function expectFailure(label:String, expected:String, fn:Void->Void):Void {
		try {
			fn();
			throw '$label did not fail';
		} catch (error:Dynamic) {
			var message = Std.string(error);
			if (message.indexOf(expected) == -1)
				throw '$label failed with unexpected error: $message';
		}
	}

	static public function main() {
		final haxiom = new Haxiom();
		haxiom.importWhitelist = ["interfaces.*"];

		// 1. Test source construction
		var source = resource("typed_plugin");
		haxiom.interpret(source);
		var plugin:IPlugin = haxiom.construct("plugins.example.Plugin");
		plugin.doSomething();
		if (plugin.calc(1, 2) != 3 || plugin.pluginName != "typed-plugin")
			throw "Source proxy method/property delegation failed";
		plugin.counter = 41;
		if (plugin.counter != 41)
			throw "Source proxy property assignment failed";

		// 2. Test bytecode construction
		var bytes = haxiom.compileToBytecodeBytes(source, new ScriptContext("Plugin", "plugin/Plugin.hx"));
		final haxiom2 = new Haxiom();
		haxiom2.importWhitelist = ["interfaces.*"];
		haxiom2.executeBytecodeBytes(bytes);
		var bytecodePlugin = haxiom2.construct("plugins.example.Plugin", IPlugin);
		bytecodePlugin.doSomething();
		if (bytecodePlugin.calc(10, 20) != 30 || bytecodePlugin.pluginName != "typed-plugin")
			throw "HXBC proxy method/property delegation failed";

		var astEngine = new Haxiom();
		astEngine.useVM = false;
		astEngine.importWhitelist = ["interfaces.*"];
		astEngine.interpret(source);
		var astPlugin:IPlugin = astEngine.construct("plugins.example.Plugin");
		astPlugin.counter = 9;
		if (astPlugin.calc(2, 3) != 5 || astPlugin.counter != 9)
			throw "AST proxy method/property delegation failed";

		// 3. Contract failures occur at construct(), not on first method call.
		var noInterface = new Haxiom();
		noInterface.interpret(resource("no_interface_plugin"));
		expectFailure("undeclared interface", "does not implement host interface", () -> {
			var _:IPlugin = noInterface.construct("NoInterfacePlugin");
		});

		var badSignature = new Haxiom();
		badSignature.importWhitelist = ["interfaces.*"];
		badSignature.interpret(resource("bad_signature_plugin"));
		expectFailure("bad signature", "argument a has type String", () -> {
			var _:IPlugin = badSignature.construct("BadSignaturePlugin");
		});

		var requiredConstructor = new Haxiom();
		requiredConstructor.importWhitelist = ["interfaces.*"];
		requiredConstructor.interpret(resource("required_constructor_plugin"));
		expectFailure("required constructor", "requires constructor arguments", () -> {
			var _:IPlugin = requiredConstructor.construct("RequiredConstructorPlugin");
		});

		expectFailure("invalid class path", "Invalid guest class name", () -> {
			var _:IPlugin = haxiom.construct("plugins.example.Plugin;trace('injected')");
		});

		var disposed = new Haxiom();
		disposed.dispose();
		expectFailure("disposed engine", "disposed", () -> {
			var _:IPlugin = disposed.construct("Plugin");
		});

		var disposedProxyEngine = new Haxiom();
		disposedProxyEngine.importWhitelist = ["interfaces.*"];
		disposedProxyEngine.interpret(source);
		var disposedProxy:IPlugin = disposedProxyEngine.construct("plugins.example.Plugin");
		disposedProxyEngine.dispose();
		expectFailure("disposed proxy", "disposed", () -> disposedProxy.doSomething());

		trace("Typed interface construct tests passed");
	}
}
