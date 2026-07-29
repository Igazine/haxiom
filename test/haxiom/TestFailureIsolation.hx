package haxiom;

import haxiom.guest.HaxiomHost;

class TestFailureIsolation {
	static var failures:Array<String> = [];

	static function main():Void {
		trace("Haxiom CPP Failure Isolation Suite");
		trace("-----------------------------------");

		runSync("Safe casts", testSafeCasts);
		runSync("AST and bytecode persistence", testPersistence);
		runSync("FFI package auto-registration", testAutoFFIPackageRegistration);
		runSync("Internal optimizer and VM tests", testInternalTests);
		runSync("Follow-up suite: compilation features", () -> TestCompilationFeatures.runTests());
		runSync("Follow-up suite: HXBC security debug", () -> TestHXBCSecurityDebug.runTests());
		runSync("Follow-up suite: static type checker", () -> TestStaticTypeChecker.runTests());
		runSync("Follow-up suite: DCE", () -> TestDCE.runTests());
		runSync("Follow-up suite: regression samples", () -> TestRegressionSamples.runTests());
		runSync("Follow-up suite: inline cache", () -> TestInlineCache.main());
		runSync("Follow-up suite: safeguards and TCO", () -> TestSafeguardsTCO.runTests());
		runSync("Follow-up suite: namespace conflicts", () -> TestNSConflict.main());
		runSync("Follow-up suite: externs", () -> TestExterns.runTests());
		runSync("Follow-up suite: caller identification", () -> TestCallerIdentification.runTests());
		runSync("Runtime static state scan", () -> TestRuntimeStaticState.runTests());
		runSync("Low-level VM state transitions", testVMStateTransitions);
		runSync("HaxiomHost.await host guard", testHostAwaitGuard);

		if (failures.length > 0) {
			throw "Failure isolation suite found " + failures.length + " synchronous failure(s):\n" + failures.join("\n\n");
		}

		trace("Starting async VM isolation suite...");
		TestAsyncVM.runTests(() -> {
			trace("ALL ISOLATED TESTS COMPLETED SUCCESSFULLY!");
		});
	}

	static function runSync(name:String, fn:Void->Void):Void {
		trace("CASE START: " + name);
		try {
			fn();
			trace("CASE PASS: " + name);
		} catch (e:Dynamic) {
			var msg = "CASE FAIL: " + name + "\n" + Std.string(e) + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			failures.push(msg);
			trace(msg);
		}
	}

	static function testSafeCasts():Void {
		var setup = "
			class Animal { public function new() {} }
			class Dog extends Animal { public function new() { super(); } }
			class Cat extends Animal { public function new() { super(); } }

			var d:Animal = new Dog();
		";
		var script = setup + "
			var dog:Dog = cast(d, Dog);

			var isCastError = false;
			try {
				var cat:Cat = cast(d, Cat);
			} catch (e:Dynamic) {
				isCastError = true;
			}
			if (!isCastError) throw 'Expected cast error for invalid cast';

			var dogRaw:Dynamic = cast d;
		";

		var astEngine = new Haxiom();
		astEngine.useVM = false;
		astEngine.interpret(setup);
		var storedD:Dynamic = astEngine.getGlobal("d");
		if (!Std.isOfType(storedD, haxiom.HaxiomTypes.HaxiomInstance)) {
			throw "AST setup stored d as " + (storedD == null ? "null" : Type.getClassName(Type.getClass(storedD))) + " value=" + Std.string(storedD);
		}
		astEngine.interpret("var dog:Dog = cast(d, Dog);");
		astEngine.interpret("
			var isCastError = false;
			try {
				var cat:Cat = cast(d, Cat);
			} catch (e:Dynamic) {
				isCastError = true;
			}
			if (!isCastError) throw 'Expected cast error for invalid cast';
		");
		astEngine.interpret("var dogRaw:Dynamic = cast d;");

		astEngine = new Haxiom();
		astEngine.useVM = false;
		astEngine.interpret(script);

		var vmEngine = new Haxiom();
		vmEngine.useVM = true;
		vmEngine.interpret(script);
	}

	static function testPersistence():Void {
		var persistEngine = new Haxiom();
		var script = "
			var factor = 5;
			var closure = (x) -> x * factor;
			var sum = 0;
			for (i in 1...4) {
				sum += closure(i);
			}
			var switchRes = 'none';
			var val = 100;
			switch (val) {
				case 100 if (factor == 5): switchRes = 'hundred';
				default: switchRes = 'other';
			}
			var res = { sum: sum, switchRes: switchRes };
			res;
		";

		var astBytes = persistEngine.compileToASTBytes(script);
		if (astBytes == null)
			throw "Failed to compile AST to bytes";

		var astLoaderEngine = new Haxiom();
		var astResult:Dynamic = astLoaderEngine.executeASTBytes(astBytes);
		if (astResult.sum != 30)
			throw "AST persistence execution failed: sum=" + astResult.sum;
		if (astResult.switchRes != "hundred")
			throw "AST persistence execution failed: switchRes=" + astResult.switchRes;

		var virtualResourceBytes = haxe.io.Bytes.alloc(6);
		var virtualResourceValues = [0, 1, 127, 128, 254, 255];
		for (i in 0...virtualResourceValues.length)
			virtualResourceBytes.set(i, virtualResourceValues[i]);
		persistEngine.addResource("virtual_binary_payload.bin", virtualResourceBytes);

		var virtualResourceScript = '
			import haxe.io.Bytes;
			class VirtualResourceDemo {
				@:haxiom.resource("virtual_binary_payload.bin")
				public var binAsset:Bytes;
				public function new() {}
			}
			var demo = new VirtualResourceDemo();
			demo.binAsset.length + "|" + demo.binAsset.get(0) + "|" + demo.binAsset.get(2) + "|" + demo.binAsset.get(3) + "|" + demo.binAsset.get(4) + "|" + demo.binAsset.get(5);
		';
		var virtualAstPayload = persistEngine.compileToASTBytes(virtualResourceScript, "virtual_ast_resource_test.hx");
		if (virtualAstPayload == null)
			throw "Failed to compile virtual AST resource script to bytes";
		var virtualAstResult:String = new Haxiom().executeASTBytes(virtualAstPayload);
		if (virtualAstResult != "6|0|127|128|254|255")
			throw "AST virtual binary resource persistence failed: " + virtualAstResult;

		var virtualBytecodeKey:HXBCKey = "virtual_binary_resource_key";
		var virtualBytecodePayload = persistEngine.compileToBytecodeBytes(virtualResourceScript, "virtual_bytecode_resource_test.hx", virtualBytecodeKey, false, true);
		if (virtualBytecodePayload == null)
			throw "Failed to compile virtual bytecode resource script to bytes";
		var encryptedInfo = Haxiom.inspectBytecode(virtualBytecodePayload);
		if (encryptedInfo.status != "ENCRYPTED")
			throw "Expected encrypted virtual binary resource bytecode inspection without key, got: " + encryptedInfo.status;
		if (!encryptedInfo.isCompressed)
			throw "Expected virtual binary resource bytecode to be compressed";
		var decryptedInfo = Haxiom.inspectBytecode(virtualBytecodePayload, virtualBytecodeKey);
		if (decryptedInfo.status != "VALID")
			throw "Expected valid virtual binary resource bytecode inspection with key, got: " + decryptedInfo.status + " " + decryptedInfo.error;
		if (!decryptedInfo.isEncrypted)
			throw "Expected virtual binary resource bytecode to report encrypted flag";
		var foundVirtualBytecodeResource = false;
		if (decryptedInfo.embeddedResources != null) {
			for (resource in decryptedInfo.embeddedResources) {
				if (resource.path == "virtual_binary_payload.bin" && resource.size == 6) {
					foundVirtualBytecodeResource = true;
					break;
				}
			}
		}
		if (!foundVirtualBytecodeResource)
			throw "Bytecode inspection failed to preserve virtual binary resource metadata";
		var virtualBytecodeResult:String = new Haxiom().executeBytecodeBytes(virtualBytecodePayload, null, virtualBytecodeKey);
		if (virtualBytecodeResult != "6|0|127|128|254|255")
			throw "Bytecode virtual binary resource persistence failed: " + virtualBytecodeResult;

		#if sys
		var astResourcePath = "test/haxiom/tmp_ast_resource_" + Std.int(haxe.Timer.stamp() * 1000000) + "_" + Std.random(1000000) + ".bin";
		var astResourceBytes = haxe.io.Bytes.alloc(5);
		for (i in 0...5)
			astResourceBytes.set(i, i * 17);
		sys.io.File.saveBytes(astResourcePath, astResourceBytes);

		var resourceScript = '
			import haxe.io.Bytes;
			class ResourceDemo {
				@:haxiom.resource("' + astResourcePath + '")
				public var binAsset:Bytes;
				public function new() {}
			}
			var demo = new ResourceDemo();
			demo.binAsset.length + "|" + demo.binAsset.get(3);
		';
		var astResourcePayload = persistEngine.compileToASTBytes(resourceScript, "ast_resource_test.hx");
		if (astResourcePayload == null)
			throw "Failed to compile AST resource script to bytes";
		var astResourceResult:String = new Haxiom().executeASTBytes(astResourcePayload);
		if (astResourceResult != "5|51")
			throw "AST binary resource persistence failed: " + astResourceResult;
		if (sys.FileSystem.exists(astResourcePath))
			sys.FileSystem.deleteFile(astResourcePath);
		#end

		var bytecodeBytes = persistEngine.compileToBytecodeBytes(script);
		if (bytecodeBytes == null)
			throw "Failed to compile Bytecode to bytes";

		if (bytecodeBytes.getString(0, 4) != "HXBC")
			throw "Bytecode persistence failed: missing HXBC header";
		if (bytecodeBytes.get(4) != 1)
			throw "Bytecode persistence failed: expected version 1, got " + bytecodeBytes.get(4);

		var corruptedBytes = haxe.io.Bytes.alloc(bytecodeBytes.length);
		corruptedBytes.blit(0, bytecodeBytes, 0, bytecodeBytes.length);
		if (bytecodeBytes.length > 13)
			corruptedBytes.set(bytecodeBytes.length - 1, corruptedBytes.get(bytecodeBytes.length - 1) ^ 0xAA);

		var checksumErrorOccurred = false;
		try {
			var bcLoaderEngine = new Haxiom();
			bcLoaderEngine.useVM = true;
			bcLoaderEngine.executeBytecodeBytes(corruptedBytes);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("checksum verification failed") != -1)
				checksumErrorOccurred = true;
		}
		if (!checksumErrorOccurred)
			throw "Expected bytecode checksum verification error on corrupted bytes, but none occurred";

		var bcLoaderEngine = new Haxiom();
		bcLoaderEngine.useVM = true;
		var bcResult:Dynamic = bcLoaderEngine.executeBytecodeBytes(bytecodeBytes);
		if (bcResult.sum != 30)
			throw "Bytecode persistence execution failed: sum=" + bcResult.sum;
		if (bcResult.switchRes != "hundred")
			throw "Bytecode persistence execution failed: switchRes=" + bcResult.switchRes;

		var scriptError = "
			var a = 200;
			throw 'Bytecode Explicit Error!';
		";
		var errCompileEngine = new Haxiom();
		var errBytes = errCompileEngine.compileToBytecodeBytes(scriptError, "error_bytecode.hx", null, true);
		var errRunEngine = new Haxiom();
		errRunEngine.useVM = true;
		var persistErrorOccurred = false;
		try {
			errRunEngine.executeBytecodeBytes(errBytes, scriptError);
		} catch (e:ScriptException) {
			persistErrorOccurred = true;
			if (e.line != 3)
				throw "Bytecode persistence expected error on line 3 but got: " + e.line;
			if (e.file != "error_bytecode.hx")
				throw "Bytecode persistence expected file name error_bytecode.hx but got: " + e.file;
			if (e.message.indexOf("throw 'Bytecode Explicit Error!'") == -1)
				throw "Bytecode persistence expected code frame with source line but got: " + e.message;
		}
		if (!persistErrorOccurred)
			throw "Expected bytecode runtime error, but none occurred";
	}

	static function testAutoFFIPackageRegistration():Void {
		var script = "
			import haxiom.autofiffi.TestClass;
			import haxiom.autofiffi.TestAbstract;

			var inst = new TestClass(42);
			if (inst.getValue() != 42) throw 'Auto-registered TestClass failed';

			if (TestClass.MY_CONSTANT != 999) throw 'Auto-registered static constant failed';

			var absVal:TestAbstract = 100;
			var rawVal:Int = absVal;
			if (rawVal != 100) throw 'Auto-registered TestAbstract casting failed';
		";

		var astEngine = new Haxiom();
		astEngine.importWhitelist = ["haxiom.autofiffi.*"];
		astEngine.registerExposedClasses();
		astEngine.useVM = false;
		astEngine.interpret(script);

		var vmEngine = new Haxiom();
		vmEngine.importWhitelist = ["haxiom.autofiffi.*"];
		vmEngine.registerExposedClasses();
		vmEngine.useVM = true;
		vmEngine.interpret(script);
	}

	static function testInternalTests():Void {
		InternalTests.run(new Haxiom());
	}

	static function testVMStateTransitions():Void {
		var engine = new Haxiom();
		if (engine.state != VMState.UNINITIALIZED)
			throw "Expected state UNINITIALIZED on new engine, got " + engine.state;

		engine.interpret("var x = 10; x + 5;");
		if (engine.state != VMState.IDLE)
			throw "Expected state IDLE after execution, got " + engine.state;

		var threwError = false;
		try {
			engine.interpret("throw 'Simulated Failure';");
		} catch (e:Dynamic) {
			threwError = true;
		}
		if (!threwError)
			throw "Expected script exception during failure test";
		if (engine.state != VMState.HALTED)
			throw "Expected state HALTED after exception, got " + engine.state;

		engine.interpret("1 + 1;");
		if (engine.state != VMState.IDLE)
			throw "Expected state IDLE after auto-reset re-evaluation";

		engine.reset();
		if (engine.state != VMState.UNINITIALIZED)
			throw "Expected state UNINITIALIZED after reset(), got " + engine.state;

		engine.interpret("100;");
		if (engine.state != VMState.IDLE)
			throw "Expected state IDLE after re-evaluation post-reset";

		engine.dispose();
		if (engine.state != VMState.DISPOSED)
			throw "Expected state DISPOSED after dispose(), got " + engine.state;

		var disposedError = false;
		try {
			engine.interpret("1;");
		} catch (e:Dynamic) {
			disposedError = Std.string(e).indexOf("disposed") != -1;
		}
		if (!disposedError)
			throw "Expected disposed engine execution error";

		engine.reset();
		if (engine.state != VMState.DISPOSED)
			throw "Disposed engine should remain DISPOSED after reset";
	}

	static function testHostAwaitGuard():Void {
		var hostAwaitError = false;
		try {
			HaxiomHost.await(null);
		} catch (e:Dynamic) {
			hostAwaitError = Std.string(e).indexOf("can only be used inside Haxiom guest scripts") != -1;
		}
		if (!hostAwaitError)
			throw "HaxiomHost.await did not throw when executed in host code";

		var futureVerifyScript = "
			import haxiom.guest.Future;
			var fut = new Future();
			fut.resolve('test');
			fut;
		";
		var engine = new Haxiom();
		engine.useVM = false;
		var fut:Dynamic = engine.interpret(futureVerifyScript);
		if (fut == null)
			throw "Guest Future construction returned null";
	}
}
