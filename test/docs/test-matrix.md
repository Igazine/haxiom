# Haxiom Test Matrix

This matrix describes the intended test coverage shape for the developer preview. It is a planning document for splitting the current large suites into smaller, faster failure-isolation groups over time.

## Current Gates

| Gate | Purpose |
| --- | --- |
| `haxe test_release.hxml` | Sequential aggregate for the developer-preview release bar. |
| `haxe build.hxml` | Fast local sanity gate using the failure-isolation suite on the interpreter target. |
| `haxe test_full.hxml` | Full interpreter gate plus bytecode CLI smoke tests. |
| `haxe test_platforms.hxml` | Active CPP, JavaScript, and Neko platform gate. |
| `haxe test/haxiom/scenarios/build.hxml` | Haxe-valid application scenarios across interpreter, CPP, JavaScript, and Neko. |
| `haxe test/haxiom/scenarios/test.hxml` | Fast interpreter-only form of the application scenario suite. |
| `haxe test/haxiom/regression/build.hxml` | Focused Haxe-valid regression corpus across interpreter, CPP, JavaScript, and Neko. |
| `haxe test/haxiom/regression/test.hxml` | Fast interpreter-only form of the focused regression corpus. |
| `haxe test_cli.hxml` | Bytecode CLI compile, inspect, and compressed bytecode smoke test. |
| `haxe test_supporting.hxml` | Sequential aggregate for the supporting example and integration smoke gates. |

## Supporting Gates

| Gate | Purpose |
| --- | --- |
| `haxe test/haxiom/compile_example.hxml` | Runs the bytecode compilation example without leaving generated files behind. |
| `haxe test/haxiom/bundle/run_bundle.hxml` | Compiles and executes the bytecode bundle fixture from an isolated temp workspace. |
| `haxe test/haxiom/interfacing/build.hxml` | Compiles and runs the host/interface bytecode construction smoke. |
| `haxe test/haxiom/build_cpp.hxml` | Compiles and runs the CPP multi-thread instance-isolation smoke. |

## Coverage Groups

| Group | Existing Coverage | Desired Direction |
| --- | --- | --- |
| Lexer and parser | `TestHaxiom`, `TestParseTypes`, syntax checks in `TestCompilationFeatures` | Split into focused parser fixtures for syntax, comments, metadata, imports, packages, and errors. |
| AST interpreter | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Every regression sample runs with `useVM = false`; continue extracting focused parser/runtime cases. |
| VM execution | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Every regression sample runs with `useVM = true`; continue extracting focused VM cases. |
| AST persistence | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Every regression sample round-trips through AST bytes; extend fixture-backed resource coverage, including `Bytes` payloads. |
| HXBC bytecode | `TestHaxiom`, `TestFailureIsolation`, `TestBytecodeCLI`, `TestRegressionSamples` | Every regression sample runs through raw and compressed HXBC; retain CLI inspection and corrupted-byte rejection gates. |
| Embedded resources | `TestHaxiom`, `TestFailureIsolation`, `TestScenarios` | Extend deterministic in-memory text and binary resource scenarios; add target-specific file fixtures only where useful. |
| FFI and host interop | `TestHaxiom`, `TestExterns`, `TestCompilationFeatures`, macro package exposure in hxml | Split host globals, exposed values, exposed classes, externs, and package auto-registration. |
| Type system | `TestTypeSystem`, `TestStaticTypeChecker`, `TestParseTypes`, `TestHaxiom` | Separate runtime type checks from opt-in static type checking. |
| Optimizer and DCE | `TestDCE`, `InternalTests` | Keep optimizer behavior tested structurally and through runtime equivalence. |
| Async and fibers | `TestAsyncVM` | Keep VM async tests isolated from synchronous platform gates where target support differs. |
| Security and sandbox | `TestHXBCSecurityDebug`, `TestSafeguardsTCO`, `TestNSConflict`, `TestCallerIdentification` | Keep sandbox tests explicit: blocked APIs, namespace halting, caller identity, limits, debug leakage. |
| Release-bar integrity | `TestReleaseBarAudit` | Keep source-level guards for accidentally commented-out core test calls in the release gate. |
| Target parity | `test_platforms.hxml` | Add smaller target-specific hxml gates once the large suites are split. |
| OpenFL integration | `test/haxiom/openfl` | Keep as integration smoke, separate from core engine gates. |

## Regression Sample Policy

Regression samples should be small scripts that prove one behavior through all supported execution paths:

- AST interpretation
- VM interpretation
- AST byte persistence
- raw HXBC bytecode
- compressed HXBC bytecode

Samples should avoid host filesystem access unless the test is explicitly `#if sys`. Cross-target samples should be pure guest scripts with deterministic scalar or string results.

Each sample declares one expected outcome: a value, a compiler failure, or a runtime failure. Failure samples must also preserve their source label through every execution path. The corpus runs twice with fresh engine instances to detect leaked mutable runtime state.

## Application Scenario Policy

Application scenarios combine features into deterministic, Haxe-valid modules resembling real guest programs. They must put executable code in a module-matching class entry point; new scenarios must not rely on Haxiom's temporary support for top-level executable code.

Application-equivalence scenarios run twice with fresh engine instances through AST interpretation, VM interpretation, AST persistence, raw HXBC, compressed HXBC, and keyed compressed HXBC. Explicit VM-interpreter stress scenarios may use recursion depths that the recursive AST evaluator and deserialized HXBC function wrappers cannot execute portably on native debug builds. The suite covers host interop, stateful workflows, inheritance and properties, JSON and collections, text and binary resources, recursion, closures, exceptions, and larger iterative workloads.
