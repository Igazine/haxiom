package haxiom;

import haxiom.BytecodeCompiler;
import haxiom.VM;
import haxiom.Interp;
import haxiom.AST;

@:keep
class InternalTests {
	public static function run(haxiom:Haxiom):Void {
		trace("Running package-internal engine tests...");
		runPeepholeTests(haxiom);
		runBytecodeSerializationTests(haxiom);
		runSlotReuseTests(haxiom);
		runScopePoolTests(haxiom);
		runBytecodeVerifierTests(haxiom);
	}

	static function runPeepholeTests(haxiom:Haxiom) {
		var script69_opt1 = "
			var y = 100;
			y;
		";
		var ast1 = haxiom.compile(script69_opt1);
		var chunk1 = BytecodeCompiler.compile(ast1, null, true, false, false);
		var insts1 = chunk1.instructions;
		
		var foundGetLocalPop = false;
		var i = 0;
		while (i < insts1.length - 2) {
			if (insts1[i] == 2 && insts1[i + 2] == 42) {
				foundGetLocalPop = true;
				break;
			}
			i++;
		}
		if (foundGetLocalPop) {
			throw "Peephole optimization failed: redundant OP_GET_LOCAL + OP_POP not eliminated";
		}
		trace("SUCCESS: Peephole optimization (GET_LOCAL + POP elimination) verified.");

		// Test 2: Redundant Conditional JUMP to next IP conversion to POP
		var chunk2 = new VM.BytecodeChunk([29, 2], [], [], 0);
		BytecodeCompiler.optimizeChunk(chunk2);
		if (chunk2.instructions.length != 1 || chunk2.instructions[0] != 42) {
			throw "Peephole optimization failed: redundant conditional jump [29, 2] was not optimized to [42] (got: " + chunk2.instructions + ")";
		}
		trace("SUCCESS: Peephole optimization (Conditional JUMP to next IP) verified.");

		// Test 3: Redundant fall-through JUMP conversion to NOPs
		var chunk3 = new VM.BytecodeChunk([28, 2], [], [], 0);
		BytecodeCompiler.optimizeChunk(chunk3);
		if (chunk3.instructions.length != 0) {
			throw "Peephole optimization failed: redundant jump [28, 2] was not optimized to [] (got: " + chunk3.instructions + ")";
		}
		trace("SUCCESS: Peephole optimization (JUMP to next IP) verified.");

		// Test 4: Jump remapping to next IP (Pass 2 optimization)
		var chunk4 = new VM.BytecodeChunk([29, 4, 2, 0, 42], [], [], 1);
		BytecodeCompiler.optimizeChunk(chunk4);
		if (chunk4.instructions.length != 2 || chunk4.instructions[0] != 42 || chunk4.instructions[1] != 0) {
			throw "Peephole optimization failed: Pass 2 remapped jump was not optimized to [42, 0] (got: " + chunk4.instructions + ")";
		}
		trace("SUCCESS: Peephole optimization (Pass 2 remapped JUMP) verified.");
	}

	static function runBytecodeSerializationTests(bcLoaderEngine:Haxiom) {
		var script72 = "
			class Main {
				static public function main() {
					var sum = 10 + 20;
					var switchRes = 'none';
					switch(sum) {
						case 30: switchRes = 'hundred';
						default: switchRes = 'other';
					}
					return { sum: sum, switchRes: switchRes };
				}
			}
		";
		var ast72 = bcLoaderEngine.compile(script72);
		var chunk72 = BytecodeCompiler.compile(ast72);
		var chunkBytes = chunk72.getBytes();
		var deserializedChunk = VM.BytecodeChunk.fromBytes(chunkBytes);
		var directResult = bcLoaderEngine.interp.executeChunk(deserializedChunk);
		if (directResult.sum != 30)
			throw "Direct getBytes/fromBytes execution failed: sum=" + directResult.sum;
		if (directResult.switchRes != "hundred")
			throw "Direct getBytes/fromBytes execution failed: switchRes=" + directResult.switchRes;
		trace("SUCCESS: Direct getBytes/fromBytes serialization verified.");
	}

	static function runSlotReuseTests(vmEngine74:Haxiom) {
		var oldUseVM = vmEngine74.useVM;
		vmEngine74.useVM = true;
		var script74_1 = "
            class SlotTester {
                public function new() {}
                public function run():Int {
                    {
                        var a:Int = 10;
                    }
                    {
                        var b:Int = 20;
                        return b;
                    }
                }
            }
            new SlotTester().run();
        ";
		var result74_1 = vmEngine74.interpret(script74_1);
		if (result74_1 != 20) {
			vmEngine74.useVM = oldUseVM;
			throw "SlotTester run failed: " + result74_1;
		}

		var slotTesterClass:Interp.HaxiomClass = cast vmEngine74.interp.globals.get("SlotTester");
		var runMethod:Dynamic = slotTesterClass.methods.get("run");
		var chunk:VM.BytecodeChunk = runMethod.bytecodeChunk;
		vmEngine74.useVM = oldUseVM;
		if (chunk.maxSlots != 1) {
			throw "Slot reuse failed: expected maxSlots == 1, but got " + chunk.maxSlots;
		}
		trace("SUCCESS: Variable slot reuse compilation verified.");
	}

	static function runScopePoolTests(haxiom:Haxiom) {
		var poolSizeBefore = Scope.pool.length;
		var script55_pool = "
            var sum = 0;
            for (i in 0...100) {
                sum = sum + i;
            }
        ";
		haxiom.interpret(script55_pool);
		var poolSizeAfter = Scope.pool.length;
		trace("Scope pool size before: " + poolSizeBefore + ", after: " + poolSizeAfter);
		if (poolSizeAfter > 0) {
			trace("SUCCESS: Scope pooling successfully recycled scopes.");
		} else {
			throw "FAIL: Scope pooling did not recycle any scopes.";
		}
	}

	static function runBytecodeVerifierTests(verEngine:Haxiom) {
		var validScript = "var x = 10; x + 5;";
		var validBytes = verEngine.compileToBytecodeBytes(validScript);
		var validChunk = Serializer.deserializeBytecode(validBytes);

		// Test invalid opcode check
		var invalidOpcodeChunk = new VM.BytecodeChunk([99], [], [], 0);
		var invalidOpcodeCaught = false;
		try {
			BytecodeVerifier.verify(invalidOpcodeChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Invalid opcode") != -1) {
				invalidOpcodeCaught = true;
			}
		}
		if (!invalidOpcodeCaught)
			throw "Expected verification error for invalid opcode, but none occurred";

		// Test out-of-bounds constant index check
		var invalidConstChunk = new VM.BytecodeChunk([1, 5], [], [], 0);
		var invalidConstCaught = false;
		try {
			BytecodeVerifier.verify(invalidConstChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Constant index") != -1) {
				invalidConstCaught = true;
			}
		}
		if (!invalidConstCaught)
			throw "Expected verification error for out-of-bounds constant, but none occurred";

		// Test out-of-bounds local slot index check
		var invalidSlotChunk = new VM.BytecodeChunk([2, 5], [], [], 2);
		var invalidSlotCaught = false;
		try {
			BytecodeVerifier.verify(invalidSlotChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Local slot index") != -1) {
				invalidSlotCaught = true;
			}
		}
		if (!invalidSlotCaught)
			throw "Expected verification error for out-of-bounds slot, but none occurred";

		// Test out-of-bounds jump target check
		var invalidJumpChunk = new VM.BytecodeChunk([28, 50], [], [], 0);
		var invalidJumpCaught = false;
		try {
			BytecodeVerifier.verify(invalidJumpChunk);
		} catch (e:Dynamic) {
			if (Std.string(e).indexOf("Jump target") != -1) {
				invalidJumpCaught = true;
			}
		}
		if (!invalidJumpCaught)
			throw "Expected verification error for out-of-bounds jump, but none occurred";

		trace("SUCCESS: Bytecode Verification & Safety Checks verified.");
		runThreadSafetyTests();
	}

	static function runThreadSafetyTests():Void {
		#if sys
		trace("Testing Multi-Threaded Concurrent Execution & Zero Shared Static State...");
		var threadCount = 8;
		var results = new sys.thread.Deque<Bool>();

		for (i in 0...threadCount) {
			sys.thread.Thread.create(function() {
				try {
					var engine = new Haxiom();
					engine.registerStaticField("TestTarget", "val", i * 10);
					var handle = HostRef.wrap("thread_secret_" + i);
					engine.setGlobal("handle", handle);

					// Run AST interpretation
					var astRes = engine.interpret("
						var x = 0;
						for (j in 0...1000) {
							x += 1;
						}
						x;
					");
					if (astRes != 1000) {
						results.add(false);
						return;
					}

					// Run VM bytecode execution
					engine.useVM = true;
					var vmRes = engine.interpret("
						var sum = 0;
						for (k in 0...500) {
							sum += 2;
						}
						sum;
					");
					if (vmRes != 1000) {
						results.add(false);
						return;
					}

					// Verify HostRef unwrapping
					var unwrapped:Dynamic = HostRef.unwrap(handle);
					if (unwrapped != "thread_secret_" + i) {
						results.add(false);
						return;
					}

					results.add(true);
				} catch (e:Dynamic) {
					trace("Thread Error: " + e);
					results.add(false);
				}
			});
		}

		var passedCount = 0;
		for (i in 0...threadCount) {
			var res = results.pop(true);
			if (res == true) passedCount++;
		}

		if (passedCount != threadCount) {
			throw 'FAIL: Concurrent multi-threaded test failed ($passedCount / $threadCount passed)';
		}
		trace('SUCCESS: Multi-Threaded Parallel Execution verified ($passedCount / $threadCount concurrent engine threads passed cleanly).');
		#else
		trace("SKIPPED: Multi-threaded test skipped on non-sys target.");
		#end
	}
}
