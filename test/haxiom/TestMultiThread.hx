package haxiom;

import haxe.io.Bytes;

typedef ThreadResult = {
	var id:Int;
	var success:Bool;
	var error:Null<String>;
}

class TestMultiThread {
	public static function main() {
		#if sys
		trace("=================================================");
		trace(" Starting Haxiom 20-Thread Concurrent Suite...");
		trace("=================================================");

		var threadCount = Sys.args().length > 1 ? Std.parseInt(Sys.args()[1]) : 20;
		if (threadCount == null || threadCount < 1) {
			throw "Thread count must be a positive integer";
		}
		var mode = Sys.args().length > 0 ? Sys.args()[0] : "all";
		if (["construct", "ast", "compile", "execute", "execute-no-pool", "vm", "all"].indexOf(mode) == -1) {
			throw 'Unknown multi-thread test mode: $mode';
		}
		var repetitions = Sys.args().length > 2 ? Std.parseInt(Sys.args()[2]) : 1;
		if (repetitions == null || repetitions < 1) {
			throw "Repetition count must be a positive integer";
		}
		var precompiled = (mode == "execute" || mode == "execute-no-pool") ? new Haxiom().compileToBytecodeBytes(vmScript(1000)) : null;
		var results = new sys.thread.Deque<ThreadResult>();
		var startBarrier = new sys.thread.Lock();

		for (i in 0...threadCount) {
			var threadId = i;
			sys.thread.Thread.create(function() {
				startBarrier.wait();
				var errStr:Null<String>;
				try {
					errStr = runThread(threadId, mode, precompiled, repetitions);
				} catch (e:Dynamic) {
					errStr = Std.string(e);
					trace('Exception in Thread $threadId: $errStr');
				}

				if (errStr != null) {
					results.add({id: threadId, success: false, error: errStr});
				} else {
					results.add({id: threadId, success: true, error: null});
				}
			});
		}
		for (_ in 0...threadCount) {
			startBarrier.release();
		}

		var passedCount = 0;
		var finishedCount = 0;
		var failures:Array<String> = [];

		while (true) {
			var res = results.pop(false);
			if (res != null) {
				finishedCount++;
				if (res.success) {
					passedCount++;
				} else {
					failures.push('Thread ${res.id}: ${res.error}');
				}
			}

			if (finishedCount >= threadCount) {
				if (passedCount == threadCount) {
					trace('SUCCESS: All $threadCount / $threadCount concurrent engine threads executed without errors or race conditions!');
					Sys.exit(0);
				} else {
					trace('FAIL: Multi-threaded execution failed ($passedCount / $threadCount passed)');
					for (f in failures) {
						trace('  - ' + f);
					}
					Sys.exit(1);
				}
			}

			Sys.sleep(0.1);
		}
		#else
		trace("SKIPPED: Threading test skipped on non-sys target.");
		#end
	}

	#if sys
	static function runThread(threadId:Int, mode:String, precompiled:Bytes, repetitions:Int):Null<String> {
		var randVal = 1000 + (threadId * 1009);
		var engine = new Haxiom();
		engine.setDefine("thread_" + threadId, true);
		if (!engine.hasDefine("thread_" + threadId)) {
			return "Host define thread_" + threadId + " failed";
		}
		engine.addResource("res_" + threadId + ".txt", Bytes.ofString("ThreadData_" + randVal));

		if (mode == "ast" || mode == "all") {
			engine.useVM = false;
			var script = '#if thread_' + threadId + '\n' + randVal + ';\n#else\n-1;\n#end';
			var result:Dynamic = engine.interpret(script);
			if (result != randVal) {
				return 'AST result mismatch: expected $randVal, got $result';
			}
		}

		if (mode == "compile") {
			var bytes = engine.compileToBytecodeBytes(vmScript(randVal));
			if (bytes == null || bytes.length == 0) {
				return "VM compiler returned no bytecode";
			}
		}

		if (mode == "execute" || mode == "execute-no-pool") {
			engine.enablePooling = mode != "execute-no-pool";
			for (_ in 0...repetitions) {
				var result:Dynamic = engine.executeBytecodeBytes(precompiled);
				if (result != 1250) {
					return 'VM result mismatch: expected 1250, got $result';
				}
			}
		}

		if (mode == "vm" || mode == "all") {
			engine.useVM = true;
			var result:Dynamic = engine.interpret(vmScript(randVal));
			var expected = randVal + 250;
			if (result != expected) {
				return 'VM result mismatch: expected $expected, got $result';
			}
		}

		var handle = HostRef.wrap("secret_thread_" + threadId + "_" + randVal);
		engine.setGlobal("threadHandle", handle);
		if (HostRef.unwrap(handle) != "secret_thread_" + threadId + "_" + randVal) {
			return "HostRef unwrap mismatch in thread " + threadId;
		}
		engine.dispose();
		return null;
	}

	static function vmScript(value:Int):String {
		return 'var val = ' + value + '; var acc = 0; for (k in 0...50) { acc += 5; } val + acc;';
	}
	#end
}
