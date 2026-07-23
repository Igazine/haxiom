# Haxiom

Haxiom is a secure, sandboxed Haxe-in-Haxe scripting engine and bytecode Virtual Machine (VM). It allows host applications to parse, compile, optimize, and execute Haxe script code safely and dynamically at runtime.

Designed for game engines, desktop/mobile applications, UI systems, and plugin/modding frameworks, Haxiom provides a high-performance scripting layer with static type checking, Ahead-of-Time (AOT) compilation, sandboxed security, and sub-second live hot-reloading.

> [!IMPORTANT]
> Haxiom is currently in developer preview. It is stable for testing, integration, and development; however, public APIs may evolve prior to version 1.0.

---

## Documentation & GitHub Wiki

For comprehensive integration tutorials, API references, architecture guides, and language matrices, visit the official Haxiom Wiki:

* **[Haxiom Wiki Documentation Home](https://github.com/Igazine/haxiom/wiki)**

The wiki covers 12 modular documentation chapters, including:
* **[Getting Started & IDE Integration](https://github.com/Igazine/haxiom/wiki/02-Getting-Started-and-IDE-Setup)**: IDE setup, `#if !haxiom_script` dummy scope, `main()` entry points, and static scoping.
* **[Host Security & Sandboxing Architecture](https://github.com/Igazine/haxiom/wiki/03-Host-Security-and-Sandboxing)**: Sandboxed proxies, instruction budgets (`maxInstructions`), property walk filters (`setFieldAccessFilter`), and secure globals.
* **[Opaque Host Handles (`HostRef<T>`)](https://github.com/Igazine/haxiom/wiki/04-Opaque-Host-Handles-and-Custom-Types)**: Un-spoofable host references and custom type integration patterns.
* **[Language Syntax, Operators & Directives](https://github.com/Igazine/haxiom/wiki/05-Language-Syntax-and-Operators)**: Complete matrix for Haxe expressions, operators, preprocessor conditionals, keywords, and metadata.
* **[Asynchronous Scripting & Cooperative Fibers](https://github.com/Igazine/haxiom/wiki/08-Asynchronous-Scripting-and-Fibers)**: Non-blocking asynchronous execution via user-land fibers (`VMFiber`).
* **[Hot-Reloading & Live Script Development](https://github.com/Igazine/haxiom/wiki/11-Hot-Reloading-and-Live-Development)**: Sub-second hot-reloading and engine disposal lifecycle (`haxiom.dispose()`).
* **[Tooling & Bytecode CLI](https://github.com/Igazine/haxiom/wiki/12-Tooling-and-CLI)**: Bytecode compilation CLI (`haxelib run haxiom bc`), bytecode inspection (`inspect`), and LZ4 compression (`-c`).

---

## Key Features

* **Dual Execution Modes**: Choose between dynamic AST Interpretation (`useVM = false`) for instant evaluation or the high-performance Register Bytecode VM (`useVM = true`).
* **Sandboxed Host Security**: Isolate guest scripts with instruction execution budgets (`maxInstructions`), memory allocation watchdogs (`maxMemory`), property access filters (`setFieldAccessFilter`), and un-spoofable opaque handles (`HostRef<T>`).
* **Foreign Function Interface (FFI)**: Easily expose host classes, enums, functions, and objects to scripts, with macro automated package exposure (`FFIMacro.exposePackage`).
* **Cooperative Fibers & Async**: Non-blocking asynchronous execution using user-land fibers (`VMFiber`) and implicit `HaxiomHost.await()` future resolution.
* **Bytecode Tooling & Compression**: Compile scripts to compact bytecode binaries using `haxelib run haxiom bc`, with opt-in LZ4 payload compression (`-c`) and automated inspection tooling.
* **IDE & Tooling Support**: Author scripts in VS Code with full Haxe Language Server autocomplete and diagnostics using the `#if !haxiom_script` dummy scope pattern.

---

## Installation

Install Haxiom into your project using `haxelib`:

```bash
haxelib git haxiom https://github.com/Igazine/haxiom.git
```

Include Haxiom in your project build file (`build.hxml` or `project.xml`):

```hxml
-L haxiom
```

---

## Quick Start Code Examples

### 1. Basic Script Execution

```haxe
import haxiom.Haxiom;

class Main {
    static function main() {
        var engine = new Haxiom();
        engine.useVM = true; // Use the high-performance Bytecode VM
        
        var result = engine.interpret("
            function calculateTotal(items:Array<Float>):Float {
                var total = 0.0;
                for (item in items) total += item;
                return total;
            }
            return calculateTotal([10.5, 20.0, 30.25]);
        ");
        
        trace('Result: $result'); // Result: 60.75
    }
}
```

### 2. Host FFI & Global Binding

```haxe
import haxiom.Haxiom;

class Main {
    static function main() {
        var engine = new Haxiom();
        
        // Bind host functions and variables to the guest script context
        engine.setGlobal("hostValue", 42);
        engine.setGlobal("logMessage", function(msg:String) {
            trace("[HOST LOG]: " + msg);
        });
        
        engine.interpret("
            logMessage('Guest script running with host value: ' + hostValue);
        ");
    }
}
```

---

## Future Plans

I'm planning to add the following features in the future to extend functionality of Haxiom. Most of the listed items are currently in discovery/investigation phase, and it's not guaranteed that each of them will be implemented ever.

- [x] Support for `extern` keyword, so guest Haxiom scripts can access host-defined classes and methods in an LSP-safe manner without using preprocessor directives
- [ ] Static extension inside Guest Scripts
- [ ] Caller identification in the Host
- [ ] Automatic `IHaxiomModule` Interface injection for Guest Scripts
- [ ] Class/field alias with `@:native` metadata inside Haxiom scripts
- [ ] ~Boot scripts with arguments (similarly to how `Sys.args()` work on certain Haxe targets)~
- [ ] Better, more detailed configuration options for Haxiom instances
- [ ] Explicit Host vs. Guest Namespace Separation in the codebase architecture
- [ ] Step-by-Step VM Debugger & DAP (Debug Adapter Protocol) to allow remote Haxiom VM debugging
- [ ] VM State Machine - snapshotted VM state serialization, so VMs can be paused, their state saved and loaded later
- [ ] Rust Native Engine Core - Create a bare-metal, zero-GC, ultra-fast Rust-based bytecode execution engine that compiles to a standalone C-ABI static/dynamic library (`libhaxiom.a` / `.so` / `.dylib` / `.wasm`)

---

## License

Haxiom is open-source software licensed under the MIT License.
