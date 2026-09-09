package;

import haxiom.Haxiom;
import haxiom.ScriptContext;
import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Thread;

class Host {
	static function main():Void {
		// Adjust these two values for manual testing; use 1 worker as a control.
		var workers = 4;
		var executionsPerWorker = 100;
		var compiler = new Haxiom();
		var source = haxe.Resource.getString("concurrency_guest");
		if (source == null) throw "Missing bundled guest source";
		var bytecode = compiler.compileToBytecodeBytes(source, new ScriptContext("Guest"));
		if (bytecode == null) throw "Guest compilation failed";
		compiler.dispose();

		// Shared input is read-only. Each worker owns its engine and mutable guest state.
		var start = new Lock();
		var results = new Deque<String>();
		Sys.println('Starting $workers workers, $executionsPerWorker HXBC executions each');
		for (id in 0...workers) {
			var workerId = id;
			Thread.create(function() {
				var engine:Haxiom = null;
				var iteration = -1;
				var failure:String = null;
				try {
					start.wait();
					engine = new Haxiom();
					for (i in 0...executionsPerWorker) {
						iteration = i;
						var value:Dynamic = engine.executeBytecodeBytes(bytecode);
						if (value != 1250) throw 'Expected 1250, got $value';
					}
				} catch (e:Dynamic) {
					failure = 'Worker $workerId, iteration $iteration: ' + Std.string(e)
						+ "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack());
				}
				try {
					if (engine != null) engine.dispose();
				} catch (e:Dynamic) {
					failure = (failure == null ? "" : failure + "\n") + 'Worker $workerId disposal: ' + Std.string(e);
				}
				results.add(failure == null ? "" : failure);
			});
		}
		for (_ in 0...workers) start.release();
		var failures = 0;
		for (_ in 0...workers) {
			var result = results.pop(true);
			if (result != "") {
				failures++;
				Sys.println(result);
			}
		}
		Sys.println(failures == 0 ? "PASS: this run completed" : 'FAIL: $failures worker(s) failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
