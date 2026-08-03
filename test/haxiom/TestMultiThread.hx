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

		var threadCount = 20;
		var results = new sys.thread.Deque<ThreadResult>();

		for (i in 0...threadCount) {
			var threadId = i;
			sys.thread.Thread.createWithEventLoop(function() {
				var errStr:Null<String> = null;
				try {
					var randVal = 1000 + (threadId * 1009);
					var engine = new Haxiom();

					// 1. Host Defines test per thread
					engine.setDefine("thread_" + threadId, true);
					if (!engine.hasDefine("thread_" + threadId)) {
						errStr = "Host define thread_" + threadId + " failed";
					} else {
						// 2. Instance Virtual Resources test per thread
						var resourceName = "res_" + threadId + ".txt";
						var resourceData = Bytes.ofString("ThreadData_" + randVal);
						engine.addResource(resourceName, resourceData);

						// 3. AST Mode Interpretation with Thread Uniqueness
						engine.useVM = false;
						var scriptAST = '
							#if thread_' + threadId + '
							' + randVal + ';
							#else
							-1;
							#end
						';

						var astRes:Dynamic = engine.interpret(scriptAST);
						var expectedAST = randVal;
						if (astRes != expectedAST) {
							errStr = 'AST result mismatch: expected $expectedAST, got $astRes';
						} else {
							// 4. Bytecode VM Execution with Thread Uniqueness
							engine.useVM = true;
							var scriptVM = '
								var val = ' + randVal + ';
								var acc = 0;
								for (k in 0...50) {
									acc += 5;
								}
								val + acc;
							';
							var vmRes:Dynamic = engine.interpret(scriptVM);
							var expectedVM = randVal + 250;
							if (vmRes != expectedVM) {
								errStr = 'VM result mismatch: expected $expectedVM, got $vmRes';
							} else {
								// 5. HostRef & Sandbox Check
								var handle = HostRef.wrap("secret_thread_" + threadId + "_" + randVal);
								engine.setGlobal("threadHandle", handle);
								var unwrapped:Dynamic = HostRef.unwrap(handle);
								if (unwrapped != "secret_thread_" + threadId + "_" + randVal) {
									errStr = "HostRef unwrap mismatch in thread " + threadId;
								} else {
									// 6. Instance Disposal Safety
									engine.dispose();
								}
							}
						}
					}
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
}
