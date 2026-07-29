# Haxiom Test Matrix

This matrix describes the intended test coverage shape for the developer preview. It is a planning document for splitting the current large suites into smaller, faster failure-isolation groups over time.

## Current Gates

| Gate | Purpose |
| --- | --- |
| `haxe build.hxml` | Fast local sanity gate using the failure-isolation suite on the interpreter target. |
| `haxe test_full.hxml` | Full interpreter gate plus bytecode CLI smoke tests. |
| `haxe test_platforms.hxml` | Active CPP, JavaScript, and Neko platform gate. |
| `haxe test_cli.hxml` | Bytecode CLI compile, inspect, and compressed bytecode smoke test. |

## Coverage Groups

| Group | Existing Coverage | Desired Direction |
| --- | --- | --- |
| Lexer and parser | `TestHaxiom`, `TestParseTypes`, syntax checks in `TestCompilationFeatures` | Split into focused parser fixtures for syntax, comments, metadata, imports, packages, and errors. |
| AST interpreter | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Run every regression sample with `useVM = false`. |
| VM execution | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Run every regression sample with `useVM = true`. |
| AST persistence | `TestHaxiom`, `TestFailureIsolation`, `TestRegressionSamples` | Verify AST bytes round-trip and resource embedding, including `Bytes` payloads. |
| HXBC bytecode | `TestHaxiom`, `TestFailureIsolation`, `TestBytecodeCLI`, `TestRegressionSamples` | Verify raw bytecode, compressed bytecode, inspection, and corrupted-byte rejection. |
| Embedded resources | `TestHaxiom`, `TestFailureIsolation` | Add fixture-backed text and binary resources under `test/` with target-aware gates. |
| FFI and host interop | `TestHaxiom`, `TestExterns`, `TestCompilationFeatures`, macro package exposure in hxml | Split host globals, exposed values, exposed classes, externs, and package auto-registration. |
| Type system | `TestTypeSystem`, `TestStaticTypeChecker`, `TestParseTypes`, `TestHaxiom` | Separate runtime type checks from opt-in static type checking. |
| Optimizer and DCE | `TestDCE`, `InternalTests` | Keep optimizer behavior tested structurally and through runtime equivalence. |
| Async and fibers | `TestAsyncVM` | Keep VM async tests isolated from synchronous platform gates where target support differs. |
| Security and sandbox | `TestHXBCSecurityDebug`, `TestSafeguardsTCO`, `TestNSConflict`, `TestCallerIdentification` | Keep sandbox tests explicit: blocked APIs, namespace halting, caller identity, limits, debug leakage. |
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

