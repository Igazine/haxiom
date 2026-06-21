package host;

import haxiom.*;
import interfaces.IPlugin;

class Host {
	static public function main() {
		final haxiom = new Haxiom();
		haxiom.importWhitelist = ["interfaces.*"];

		// 1. Test source construction
		var source = sys.io.File.getContent("plugin/Plugin.hx");
		haxiom.interpret(source);
		var plugin = haxiom.construct(IPlugin, "Plugin");
		plugin.doSomething();
		trace(plugin.calc(1, 2));

		// 2. Test bytecode construction
		var bytes = haxiom.compileToBytecodeBytes(source, "plugin/Plugin.hx");
		sys.io.File.saveBytes("plugin/Plugin.hxbc", bytes);

		final haxiom2 = new Haxiom();
		haxiom2.importWhitelist = ["interfaces.*"];
		haxiom2.executeBytecodeBytes(bytes);
		var bytecodePlugin = haxiom2.construct(IPlugin, "Plugin");
		bytecodePlugin.doSomething();
		trace(bytecodePlugin.calc(10, 20));
	}
}
