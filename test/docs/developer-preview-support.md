# Haxiom Developer Preview Support Contract

This document defines what the current developer preview is expected to support and what remains intentionally unstable.

## Supported Targets

The primary supported Haxe targets for this preview are:

- CPP
- JavaScript
- Neko

Lua and JVM are not part of the active gate for this preview. They may compile or run in some states, but they are not release blockers until they are restored to the platform matrix.

## Supported Workflows

The following workflows are expected to work on the active targets:

- AST interpretation through `Haxiom.interpret()` with `useVM = false`.
- VM execution through `Haxiom.interpret()` with `useVM = true`.
- AST byte persistence through `compileToASTBytes()` and `executeASTBytes()`.
- HXBC bytecode persistence through `compileToBytecodeBytes()` and `executeBytecodeBytes()`.
- HXBC compression through the `compress` argument and bytecode CLI `-c` option.
- Bytecode inspection through `Haxiom.inspectBytecode()` and `haxelib run haxiom inspect`.
- Rejection of malformed or oversized persisted AST and HXBC input before execution.
- Embedded script resources through `@:haxiom.resource`, including binary `Bytes` payloads.
- Host interop through globals, exposed values, exposed classes, extern declarations, and macro-based package exposure.
- Sandbox-oriented behavior covered by the current tests: blocked host access, instruction limits, memory limits, caller identification, and namespace halting.
- Async/await VM behavior covered by the current async suite.
- DCE as the default optimization behavior, with `enableDCE = false` available as an opt-out.

## Stability Boundaries

The following are not stable API promises in this developer preview:

- Exact AST object shape and internal enum layout.
- HXBC binary format compatibility across future preview versions.
- Optimizer internals and exact bytecode instruction sequences.
- Debug symbol format and locals dump layout.
- Complete Haxe language compatibility.
- Behavior on targets outside the active matrix.

## Execution Mode Security

New `Haxiom` instances use VM mode by default. AST execution requires explicitly setting `useVM = false`.

The bytecode VM is the production execution path for untrusted scripts, deeply recursive workloads, and persisted HXBC payloads. Guest calls, constructors, accessors, declaration initializers, guards, and abstract operators execute through VM-managed frames so guest recursion does not consume the host call stack.

The AST interpreter remains supported for compatibility, diagnostics, and parser-level regression testing. It is a recursive tree-walking evaluator and is not a stack-safe security boundary for adversarial or deeply recursive input. Host applications executing untrusted scripts must use VM mode and keep the applicable instruction and memory limits enabled.

Persisted loaders default to a 64 MiB encoded/decoded size limit through `maxPersistedBytes`. Portable AST JSON additionally defaults to a nesting limit of 512 through `maxPersistedDepth`. Both limits are instance-based, reject negative configuration, and may be set to `0` when a trusted host explicitly needs unlimited input.

## Runtime Isolation Rule

Haxiom runtime state must remain instance-based. Runtime mutable state must not be stored in `static` fields. Static helper or factory functions are acceptable when they return new instances or operate only on arguments. Macros may use static structure as needed by Haxe macro conventions.

## Release Bar

A developer-preview build should pass:

- `haxe test_release.hxml`

This aggregate runs the individual release-bar gates:

- `haxe build.hxml`
- `haxe test_full.hxml`
- `haxe test_platforms.hxml`
- `haxe test_supporting.hxml`

The active gates must not contain intentionally commented-out test calls or temporary try/catch masking around failing internal tests.
`TestReleaseBarAudit` enforces the commented-out-call portion of this rule for the current high-risk `TestHaxiom.hx` calls.
