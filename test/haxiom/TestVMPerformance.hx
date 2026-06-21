package haxiom;

class TestVMPerformance {
    public static function main() {
        trace("=================================================");
        trace(" Haxiom VM Performance Benchmark ");
        trace("=================================================");

        var fibScript = "
            function fib(n) {
                if (n <= 1) return n;
                return fib(n - 1) + fib(n - 2);
            }
            fib(12);
        ";

        var loopScript = "
            var sum = 0;
            var i = 0;
            while (i < 2000) {
                var inner = (val) -> {
                    return val * 2;
                };
                sum += inner(i);
                i++;
            }
            sum;
        ";

        var tryCatchScript = "
            var count = 0;
            var i = 0;
            while (i < 1000) {
                try {
                    if (i % 2 == 0) {
                        throw 'err';
                    }
                } catch(e:String) {
                    count++;
                }
                i++;
            }
            count;
        ";

        var methodCallScript = "
            class Helper {
                public var val:Int = 0;
                public function new() {}
                public function add(x:Int) {
                    val += x;
                }
            }
            var h = new Helper();
            var i = 0;
            while (i < 5000) {
                h.add(1);
                i++;
            }
            h.val;
        ";

        runBenchmark("Recursive Fibonacci (fib(12))", fibScript, 200);
        runBenchmark("Inner Closure Iterations (2000 steps)", loopScript, 100);
        runBenchmark("Try/Catch Resolution (1000 steps)", tryCatchScript, 100);
        runBenchmark("Instance Method Calls (5000 steps)", methodCallScript, 50);
    }

    static function runBenchmark(name:String, script:String, iterations:Int) {
        trace('Running benchmark: $name ($iterations iterations)');

        var engine = new haxiom.Haxiom();
        var ast = engine.compile(script);
        var chunk = haxiom.BytecodeCompiler.compile(ast);

        // Warm up
        for (i in 0...5) {
            engine.interp.useVM = false;
            engine.execute(ast);
            
            engine.interp.useVM = true;
            haxiom.VM.enablePooling = false;
            engine.interp.executeChunk(chunk);

            haxiom.VM.enablePooling = true;
            engine.interp.executeChunk(chunk);
        }

        // 1. AST Interpreter
        engine.interp.useVM = false;
        var start = haxe.Timer.stamp();
        for (i in 0...iterations) {
            engine.execute(ast);
        }
        var astTime = haxe.Timer.stamp() - start;

        // 2. VM No Pooling
        engine.interp.useVM = true;
        haxiom.VM.enablePooling = false;
        var start = haxe.Timer.stamp();
        for (i in 0...iterations) {
            engine.interp.executeChunk(chunk);
        }
        var vmNoPoolTime = haxe.Timer.stamp() - start;

        // 3. VM With Pooling
        engine.interp.useVM = true;
        haxiom.VM.enablePooling = true;
        var start = haxe.Timer.stamp();
        for (i in 0...iterations) {
            engine.interp.executeChunk(chunk);
        }
        var vmPoolTime = haxe.Timer.stamp() - start;

        trace('  AST Interpreter Time: ' + Math.round(astTime * 1000) + 'ms');
        trace('  VM (No Pooling) Time: ' + Math.round(vmNoPoolTime * 1000) + 'ms');
        trace('  VM (With Pooling) Time: ' + Math.round(vmPoolTime * 1000) + 'ms');

        var vmVsAst = (astTime - vmPoolTime) / astTime * 100; // percent speedup
        var poolVsNoPool = (vmNoPoolTime - vmPoolTime) / vmNoPoolTime * 100;

        trace('  VM speedup over AST: ' + Math.round(vmVsAst) + '%');
        trace('  Frame Pooling speedup: ' + Math.round(poolVsNoPool) + '%');
        trace("-------------------------------------------------");
    }
}
