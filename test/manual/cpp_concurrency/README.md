# Manual C++ concurrency reproducer

Run from the repository root:

```sh
haxe test/manual/cpp_concurrency/run.hxml
```

This builds with `--debug` and runs one process. Repeat manually as needed.
To compile without running, use `test/manual/cpp_concurrency/build.hxml` instead.
Build output is under the ignored `test/haxiom/tmp_manual_concurrency/` directory.

`Host.hx` compiles the resource-bundled `Guest.hx` once, then starts four workers.
Each worker creates its own Haxiom instance and repeatedly decodes and executes
the same read-only HXBC bytes. The expected result is always 1250. There are no
shared engines, host callbacks, guest filesystem calls, or conditional guest code.
The host's locks and queue only coordinate worker startup and completion.

Edit `workers` and `executionsPerWorker` near the top of `Host.hx` to vary load.
One worker provides a sequential control. Repeated executions within a process
are not equivalent to fresh process launches; the historical failure was
intermittent across fresh launches. A passing run does not establish a fix.

Haxe exceptions are caught inside each worker and reported with its ID, iteration,
and exception stack. A native SIGSEGV/SIGBUS can bypass these catches and terminate
the process. Save the native crash report or debugger backtrace, terminal output,
worker/iteration settings, and Haxe/hxcpp versions when reporting a failure.

This is a reduced version of `test/haxiom/TestMultiThread.hx`'s `execute` mode,
not a proven deterministic reproducer. The original broader suite remains intact.
It is not included in the automated release gate.
