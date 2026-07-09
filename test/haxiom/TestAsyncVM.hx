package haxiom;

import haxiom.Haxiom;
import haxiom.Future;
import haxe.Timer;

class TestAsyncVM {
    static function delay(ms:Int, val:Dynamic):Future {
        var fut = new Future();
        #if (eval || macro)
        fut.resolve(val);
        #else
        Timer.delay(() -> {
            fut.resolve(val);
        }, ms);
        #end
        return fut;
    }

    static function delayReject(ms:Int, err:Dynamic):Future {
        var fut = new Future();
        #if (eval || macro)
        fut.reject(err);
        #else
        Timer.delay(() -> {
            fut.reject(err);
        }, ms);
        #end
        return fut;
    }

    public static function runTests(onComplete:Void->Void) {
        trace("Starting Async/Await VM Verification Suite...");
        
        testBasicAwait(() -> {
            testNestedAwait(() -> {
                testConcurrentAwait(() -> {
                    testTryCatchAwait(() -> {
                        testUncaughtExceptionAwait(() -> {
                            testAwaitNonPromise(() -> {
                                testASTModeRejection(() -> {
                                    testAutoAsyncDetection(() -> {
                                        testDisposal(() -> {
                                            trace("SUCCESS: All Haxiom Async/Await VM tests passed!");
                                            onComplete();
                                        });
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });
    }

    static function testBasicAwait(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var script = '
            class TestClass {
                @:haxiom.async
                public static function run() {
                    var x = Haxiom.await(delay(10, 5));
                    var y = Haxiom.await(delay(10, 15));
                    return x + y;
                }
            }
            TestClass.run();
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                if (val != 20) throw "testBasicAwait failed: expected 20, got " + val;
                trace("SUCCESS: testBasicAwait passed.");
                cb();
            },
            (err) -> {
                throw "testBasicAwait failed with error: " + err;
            }
        );
    }

    static function testNestedAwait(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var script = '
            class NestedClass {
                @:haxiom.async
                public static function c(v) {
                    var r = Haxiom.await(delay(5, v * 2));
                    return r;
                }
                @:haxiom.async
                public static function b(v) {
                    var r = Haxiom.await(NestedClass.c(v));
                    return r + 5;
                }
                @:haxiom.async
                public static function a(v) {
                    var r = Haxiom.await(NestedClass.b(v));
                    return r + 10;
                }
            }
            NestedClass.a(5);
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                if (val != 25) throw "testNestedAwait failed: expected 25, got " + val;
                trace("SUCCESS: testNestedAwait passed.");
                cb();
            },
            (err) -> {
                throw "testNestedAwait failed with error: " + err;
            }
        );
    }

    static function testConcurrentAwait(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var script = '
            class ConcurrentClass {
                @:haxiom.async
                public static function run(ms, val) {
                    var x = Haxiom.await(delay(ms, val));
                    return x;
                }
            }
        ';
        engine.interpret(script);

        var runFunc:Dynamic = engine.interpret("ConcurrentClass.run;");
        var p1:Future = runFunc(30, 100);
        var p2:Future = runFunc(10, 200);

        var p1Done = false;
        var p2Done = false;

        p1.then(
            (val) -> {
                if (val != 100) throw "testConcurrentAwait p1 failed: expected 100, got " + val;
                p1Done = true;
                if (p1Done && p2Done) {
                    trace("SUCCESS: testConcurrentAwait passed.");
                    cb();
                }
            },
            (err) -> throw "testConcurrentAwait p1 failed: " + err
        );

        p2.then(
            (val) -> {
                if (val != 200) throw "testConcurrentAwait p2 failed: expected 200, got " + val;
                p2Done = true;
                if (p1Done && p2Done) {
                    trace("SUCCESS: testConcurrentAwait passed.");
                    cb();
                }
            },
            (err) -> throw "testConcurrentAwait p2 failed: " + err
        );
    }

    static function testTryCatchAwait(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delayReject", (ms:Int, err:Dynamic) -> delayReject(ms, err));

        var script = '
            class CatchClass {
                @:haxiom.async
                public static function run() {
                    var res = "none";
                    try {
                        var x = Haxiom.await(delayReject(10, "Failed!"));
                    } catch (err:String) {
                        res = "Caught: " + err;
                    }
                    return res;
                }
            }
            CatchClass.run();
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                if (val != "Caught: Failed!") throw "testTryCatchAwait failed: expected 'Caught: Failed!', got " + val;
                trace("SUCCESS: testTryCatchAwait passed.");
                cb();
            },
            (err) -> {
                throw "testTryCatchAwait failed with error: " + err;
            }
        );
    }

    static function testUncaughtExceptionAwait(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delayReject", (ms:Int, err:Dynamic) -> delayReject(ms, err));

        var script = '
            class UncaughtClass {
                @:haxiom.async
                public static function run() {
                    var x = Haxiom.await(delayReject(10, "Fatal error"));
                    return x;
                }
            }
            UncaughtClass.run();
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                throw "testUncaughtExceptionAwait should have failed, but resolved with: " + val;
            },
            (err) -> {
                if (Std.string(err) != "Fatal error") {
                    throw "testUncaughtExceptionAwait failed: expected 'Fatal error', got " + err;
                }
                trace("SUCCESS: testUncaughtExceptionAwait passed.");
                cb();
            }
        );
    }

    static function testAwaitNonPromise(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;

        var script = '
            class NonPromiseClass {
                @:haxiom.async
                public static function run() {
                    var x = Haxiom.await(123);
                    var y = Haxiom.await("hello");
                    var z = Haxiom.await(null);
                    return [x, y, z];
                }
            }
            NonPromiseClass.run();
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                var arr:Array<Dynamic> = val;
                if (arr[0] != 123 || arr[1] != "hello" || arr[2] != null) {
                    throw "testAwaitNonPromise failed: unexpected value " + val;
                }
                trace("SUCCESS: testAwaitNonPromise passed.");
                cb();
            },
            (err) -> {
                throw "testAwaitNonPromise failed with error: " + err;
            }
        );
    }

    static function testASTModeRejection(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = false;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var caughtMethodError = false;
        try {
            var script = '
                class ASTClass {
                    @:haxiom.async
                    public static function run() {
                        return 1;
                    }
                }
                ASTClass.run();
            ';
            engine.interpret(script);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("requires Haxiom VM mode") != -1) {
                caughtMethodError = true;
            } else {
                throw "testASTModeRejection unexpected method error: " + e;
            }
        }

        var caughtAwaitError = false;
        try {
            var script = '
                var x = Haxiom.await(123);
            ';
            engine.interpret(script);
        } catch (e:Dynamic) {
            if (Std.string(e).indexOf("only supported in VM execution mode") != -1) {
                caughtAwaitError = true;
            } else {
                throw "testASTModeRejection unexpected await error: " + e;
            }
        }

        if (!caughtMethodError) throw "testASTModeRejection failed: expected async method declaration in AST mode to throw";
        if (!caughtAwaitError) throw "testASTModeRejection failed: expected Haxiom.await in AST mode to throw";

        trace("SUCCESS: testASTModeRejection passed.");
        cb();
    }

    static function testAutoAsyncDetection(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var script = '
            class AutoClass {
                public static function run() {
                    var myClosure = function() {
                        var res = Haxiom.await(delay(10, 42));
                        return res;
                    };
                    
                    var x = Haxiom.await(delay(10, 8));
                    var y = Haxiom.await(myClosure());
                    return x + y;
                }
            }
            AutoClass.run();
        ';
        var promise:Future = engine.interpret(script);
        promise.then(
            (val) -> {
                if (val != 50) throw "testAutoAsyncDetection failed: expected 50, got " + val;
                trace("SUCCESS: testAutoAsyncDetection passed.");
                cb();
            },
            (err) -> {
                throw "testAutoAsyncDetection failed with error: " + err;
            }
        );
    }

    static function testDisposal(cb:Void->Void) {
        var engine = new Haxiom();
        engine.useVM = true;
        engine.setGlobal("delay", (ms:Int, val:Dynamic) -> delay(ms, val));

        var counter = 0;
        engine.setGlobal("increment", () -> {
            counter++;
        });

        var script = '
            class DisposedTest {
                public static function run() {
                    Haxiom.await(delay(15, null));
                    increment();
                    Haxiom.await(delay(15, null));
                    increment();
                }
            }
            DisposedTest.run();
        ';

        var promise:Future = engine.interpret(script);
        engine.dispose();
        
        if (!engine.disposed) throw "testDisposal failed: expected engine to be flagged as disposed";

        #if (eval || macro)
        cb();
        #else
        Timer.delay(() -> {
            if (counter != 0) {
                throw "testDisposal failed: guest script executed functions after dispose! counter = " + counter;
            }
            trace("SUCCESS: testDisposal passed.");
            cb();
        }, 50);
        #end
    }
}
