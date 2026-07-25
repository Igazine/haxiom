package haxiom;

/**
 * Represents the low-level lifecycle state of a Haxiom engine instance.
 */
enum VMState {
	/** Engine instantiated; no script evaluated yet. */
	UNINITIALIZED;

	/** Actively evaluating AST expressions or executing VM bytecode opcodes. */
	RUNNING;

	/** Top-level script initialized; environment retained for direct function calls and signals. */
	IDLE;

	/** Engine execution paused on a cooperative VMFiber await() suspension. */
	SUSPENDED;

	/** Stopped due to runtime error, memory limit, or instruction budget exhaustion. */
	HALTED;

	/** Teardown complete; instance pool memory and references cleared. */
	DISPOSED;
}
