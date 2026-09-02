package releaseconsumer;

import haxe.io.Bytes;
import haxiom.Haxiom;
import haxiom.HostRef;
import haxiom.HXBCKey;
import haxiom.ScriptContext;

class ReleaseApiSmoke {
	static public function main():Void {
		var source = "class ReleaseGuest { static public function main():Int return 42; }";
		var context = new ScriptContext("ReleaseGuest", "ReleaseGuest.hx");
		var engine = configuredEngine();
		var interpreted:Int = engine.interpret(source, context);
		if (interpreted != 42)
			throw 'Public source API returned $interpreted instead of 42';

		var key:HXBCKey = "release-api-smoke";
		var bytecode = engine.compileToBytecodeBytes(source, context, key, true, true);
		var info = Haxiom.inspectBytecode(bytecode, key);
		if (info.status != "VALID" || !info.isEncrypted || !info.isCompressed)
			throw 'Public HXBC API returned invalid metadata: ${info.status}';

		var bytecodeEngine = configuredEngine();
		var executed:Int = bytecodeEngine.executeBytecodeBytes(bytecode, source, key);
		if (executed != 42)
			throw 'Public HXBC API returned $executed instead of 42';

		var value = Bytes.ofString("opaque");
		var handle = HostRef.wrap(value);
		if (HostRef.unwrap(handle) != value)
			throw "Public HostRef API did not preserve host identity";
		HostRef.free(handle);
		if (HostRef.unwrap(handle) != null)
			throw "Public HostRef API did not invalidate a freed handle";

		engine.dispose();
		bytecodeEngine.dispose();
		trace("SUCCESS: External release API smoke passed.");
	}

	static function configuredEngine():Haxiom {
		var engine = new Haxiom();
		engine.debugMode = true;
		engine.enableStaticTypes = true;
		engine.maxInstructions = 100000;
		engine.maxMemory = 100000;
		engine.onCompilerError = error -> throw error;
		engine.onRuntimeError = error -> throw error;
		engine.addResource("release/payload.bin", Bytes.ofHex("001122"));
		engine.setFieldAccessFilter((_, _) -> true);
		return engine;
	}
}
