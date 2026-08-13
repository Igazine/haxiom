package haxiom;

import haxiom.VM.BytecodeChunk;
import haxe.ds.ObjectMap;

@:allow(haxiom)
class BytecodeVerifier {
	static function verify(chunk:BytecodeChunk):Void {
		if (chunk == null)
			throw "Cannot verify null bytecode chunk";

		var pending = [chunk];
		var seen = new ObjectMap<BytecodeChunk, Bool>();
		while (pending.length > 0) {
			var current = pending[pending.length - 1];
			pending.pop();
			if (seen.exists(current))
				continue;
			seen.set(current, true);

			verifyChunk(current, pending);
		}
	}

	static function verifyChunk(chunk:BytecodeChunk, pending:Array<BytecodeChunk>):Void {
		if (chunk.maxSlots < 0)
			throw 'Invalid negative maxSlots ${chunk.maxSlots}';
		if (chunk.maxSlots > 1048576)
			throw 'maxSlots ${chunk.maxSlots} exceeds VM safety limit';
		if (chunk.constants == null)
			throw "Constants array is null";
		if (chunk.instructions == null)
			throw "Instructions array is null";
		if (chunk.positions == null)
			throw "Position array is null";
		if (chunk.positions.length != 0 && chunk.positions.length != chunk.instructions.length)
			throw 'Position table length ${chunk.positions.length} does not match instruction data length ${chunk.instructions.length}';

		for (i in 0...chunk.positions.length) {
			var pos = chunk.positions[i];
			if (pos != null && (pos.line < 0 || pos.col < 0))
				throw 'Invalid source position at instruction index $i';
		}

		collectNestedChunks(chunk.constants, pending);

		var inst = chunk.instructions;
		var starts = [for (_ in 0...inst.length) false];
		var nextByIp = [for (_ in 0...inst.length) -1];
		var requiredByIp = [for (_ in 0...inst.length) 0];
		var deltaByIp = [for (_ in 0...inst.length) 0];
		var branchByIp = [for (_ in 0...inst.length) -1];
		var catchByIp = [for (_ in 0...inst.length) -1];
		var terminal = [for (_ in 0...inst.length) false];
		var unconditional = [for (_ in 0...inst.length) false];

		var ip = 0;
		while (ip < inst.length) {
			var start = ip;
			starts[start] = true;
			var op:Int = inst[ip++];
			if (op < 0 || op > 77)
				throw 'Invalid opcode $op at instruction index $start';

			var required = 0;
			var delta = 0;
			switch (op) {
				case 1: // OP_LOAD_CONST
					checkOperands(ip, 1, inst.length);
					checkConstIndex(inst[ip++], chunk);
					delta = 1;

				case 2: // OP_GET_LOCAL
					checkOperands(ip, 1, inst.length);
					checkSlotIndex(inst[ip++], chunk);
					delta = 1;

				case 3: // OP_SET_LOCAL
					checkOperands(ip, 1, inst.length);
					checkSlotIndex(inst[ip++], chunk);
					required = 1;

				case 4, 5: // OP_GET_VAR, OP_SET_VAR
					checkOperands(ip, 1, inst.length);
					checkStringConst(inst[ip++], chunk, "variable name");
					if (op == 4)
						delta = 1;
					else
						required = 1;

				case 6: // OP_DECLARE_VAR
					checkOperands(ip, 3, inst.length);
					checkStringConst(inst[ip++], chunk, "variable name");
					var typeIdx = inst[ip++];
					if (typeIdx >= 0)
						checkConstIndex(typeIdx, chunk);
					var isFinal = inst[ip++];
					if (isFinal != 0 && isFinal != 1)
						throw 'Invalid final flag $isFinal at instruction index ${ip - 1}';
					required = 1;
					delta = -1;

				case 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27:
					required = 2;
					delta = -1;

				case 20, 24: // unary operators
					required = 1;

				case 28, 29, 30, 31, 32: // jumps
					checkOperands(ip, 1, inst.length);
					var target = inst[ip++];
					checkJumpRange(target, inst.length);
					branchByIp[start] = target;
					if (op == 28)
						unconditional[start] = true;
					else {
						required = 1;
						if (op == 29)
							delta = -1;
					}

				case 33: // OP_CALL
					checkOperands(ip, 1, inst.length);
					var count = inst[ip++];
					checkNonNegative(count, "argument count", ip - 1);
					required = count + 1;
					delta = -count;

				case 34, 39: // OP_RETURN, OP_THROW
					required = 1;
					terminal[start] = true;

				case 35, 57: // OP_GET_FIELD, OP_SAFE_GET_FIELD
					checkOperands(ip, 1, inst.length);
					checkStringConst(inst[ip++], chunk, "field name");
					required = 1;

				case 36, 58: // OP_SET_FIELD, OP_SAFE_SET_FIELD
					checkOperands(ip, 1, inst.length);
					checkStringConst(inst[ip++], chunk, "field name");
					required = 2;
					delta = -1;

				case 37: // OP_NEW_ARRAY
					checkOperands(ip, 1, inst.length);
					var count = inst[ip++];
					checkNonNegative(count, "element count", ip - 1);
					required = count;
					delta = 1 - count;

				case 38: // OP_NEW_OBJECT
					checkOperands(ip, 1, inst.length);
					var fieldCount = inst[ip++];
					checkNonNegative(fieldCount, "object field count", ip - 1);
					checkOperands(ip, fieldCount, inst.length);
					for (_ in 0...fieldCount)
						checkStringConst(inst[ip++], chunk, "object field name");
					required = fieldCount;
					delta = 1 - fieldCount;

				case 40, 41, 53, 60, 61, 62, 63, 64, 65, 66, 67, 75, 77:
					if (op == 41) { // OP_MAKE_FUNCTION
						checkOperands(ip, 1, inst.length);
						checkFunctionPrototype(inst[ip++], chunk);
					} else if (op == 53) { // OP_UNOP_MUTATE
						checkOperands(ip, 2, inst.length);
						checkStringConst(inst[ip++], chunk, "unary operator");
						checkExprConst(inst[ip++], chunk, "unary mutation target");
					} else if (op >= 60 && op <= 67) {
						checkOperands(ip, 1, inst.length);
						checkExprConst(inst[ip++], chunk, "declaration");
					} else if (op == 75) { // OP_EREG
						checkOperands(ip, 2, inst.length);
						checkStringConst(inst[ip++], chunk, "regular expression pattern");
						checkStringConst(inst[ip++], chunk, "regular expression flags");
					} else if (op == 77) { // OP_RESOLVE_PATH
						checkOperands(ip, 1, inst.length);
						checkExprConst(inst[ip++], chunk, "path expression");
					}
					delta = 1;

				case 42: // OP_POP is intentionally tolerant of an empty stack.
					delta = -1;

				case 76: // OP_ON_DISPOSE
					required = 1;
					delta = -1;

				case 45: // OP_GET_ITERATOR
					required = 1;

				case 46, 47: // iterator peek operations
					required = 1;
					delta = 1;

				case 48: // OP_PUSH_TRY
					checkOperands(ip, 1, inst.length);
					var target = inst[ip++];
					checkJumpRange(target, inst.length);
					catchByIp[start] = target;

				case 50: // OP_MATCH_CASE
					checkOperands(ip, 2, inst.length);
					checkExprConst(inst[ip++], chunk, "match pattern");
					var guardIdx = inst[ip++];
					if (guardIdx >= 0)
						checkChunkConst(guardIdx, chunk, "match guard");
					required = 1;
					delta = 1;

				case 51: // OP_MATCH_CATCH
					checkOperands(ip, 1, inst.length);
					checkCatchClause(inst[ip++], chunk);
					required = 1;
					delta = 1;

				case 52: // OP_UNOP
					checkOperands(ip, 1, inst.length);
					checkStringConst(inst[ip++], chunk, "unary operator");
					required = 1;

				case 54, 71: // OP_ARRAY_ACCESS_GET, OP_RANGE
					required = 2;
					delta = -1;

				case 55: // OP_ARRAY_ACCESS_SET
					required = 3;
					delta = -2;

				case 56: // OP_NEW
					checkOperands(ip, 2, inst.length);
					checkConstIndex(inst[ip++], chunk);
					var count = inst[ip++];
					checkNonNegative(count, "constructor argument count", ip - 1);
					required = count;
					delta = 1 - count;

				case 59: // OP_CAST
					checkOperands(ip, 1, inst.length);
					var typeIdx = inst[ip++];
					if (typeIdx >= 0)
						checkConstIndex(typeIdx, chunk);
					required = 1;

				case 68: // OP_DUP
					required = 1;
					delta = 1;

				case 69: // OP_CALL_METHOD
					checkOperands(ip, 2, inst.length);
					checkStringConst(inst[ip++], chunk, "method name");
					var count = inst[ip++];
					checkNonNegative(count, "method argument count", ip - 1);
					required = count + 1;
					delta = -count;

				case 70: // OP_NEW_MAP
					checkOperands(ip, 1, inst.length);
					var count = inst[ip++];
					checkNonNegative(count, "map element count", ip - 1);
					if (count > 0x3FFFFFFF)
						throw 'Map element count $count exceeds VM safety limit';
					required = count * 2;
					delta = 1 - required;

				case 72: // OP_PUSH_CASE_SCOPE
					required = 1;
					delta = -1;

				case 73: // OP_CHECK_TYPE
					checkOperands(ip, 1, inst.length);
					checkConstIndex(inst[ip++], chunk);
					required = 1;

				case 74: // OP_AWAIT
					if (!chunk.isAsync)
						throw 'Await opcode in non-async bytecode chunk at instruction index $start';
					required = 1;

				default:
					// Remaining defined opcodes have no operands and no data-stack effect.
			}

			nextByIp[start] = ip;
			requiredByIp[start] = required;
			deltaByIp[start] = delta;
		}

		for (source in 0...inst.length) {
			if (branchByIp[source] >= 0)
				checkJumpBoundary(source, branchByIp[source], inst.length, starts);
			if (catchByIp[source] >= 0)
				checkJumpBoundary(source, catchByIp[source], inst.length, starts);
		}

		verifyDebugSymbols(chunk, starts);
		verifyStackFlow(inst, starts, nextByIp, requiredByIp, deltaByIp, branchByIp, catchByIp, terminal, unconditional);
	}

	static function collectNestedChunks(constants:Array<Dynamic>, pending:Array<BytecodeChunk>):Void {
		for (constant in constants) {
			if (constant == null || !Reflect.isObject(constant))
				continue;
			for (field in ["bodyChunk", "guardChunk", "bytecodeChunk"]) {
				if (!Reflect.hasField(constant, field))
					continue;
				var nested = Reflect.field(constant, field);
				if (nested != null) {
					if (!Std.isOfType(nested, BytecodeChunk))
						throw 'Invalid nested bytecode field "$field"';
					pending.push(cast nested);
				}
			}
		}
	}

	static function verifyDebugSymbols(chunk:BytecodeChunk, starts:Array<Bool>):Void {
		if (chunk.debugSymbols == null)
			return;
		for (i in 0...chunk.debugSymbols.length) {
			var symbol = chunk.debugSymbols[i];
			if (symbol == null || symbol.name == null)
				throw 'Invalid debug symbol at index $i';
			if (symbol.slot < 0 || symbol.slot >= chunk.maxSlots)
				throw 'Debug symbol slot ${symbol.slot} out of bounds at index $i';
			if (symbol.startIp < 0 || symbol.endIp < symbol.startIp || symbol.endIp > chunk.instructions.length)
				throw 'Invalid debug symbol range at index $i';
			if (symbol.startIp < chunk.instructions.length && !starts[symbol.startIp])
				throw 'Debug symbol start ${symbol.startIp} is not an instruction boundary';
			if (symbol.endIp < chunk.instructions.length && !starts[symbol.endIp])
				throw 'Debug symbol end ${symbol.endIp} is not an instruction boundary';
		}
	}

	static function verifyStackFlow(instructions:Array<Int>, starts:Array<Bool>, nextByIp:Array<Int>, requiredByIp:Array<Int>, deltaByIp:Array<Int>,
			branchByIp:Array<Int>, catchByIp:Array<Int>, terminal:Array<Bool>, unconditional:Array<Bool>):Void {
		var length = instructions.length;
		if (length == 0)
			return;
		var depths = [for (_ in 0...length) -1];
		var pending = [0];
		depths[0] = 0;

		while (pending.length > 0) {
			var current = pending[pending.length - 1];
			pending.pop();
			var depth = depths[current];
			var required = requiredByIp[current];
			if (depth < required)
				throw 'Stack underflow at instruction index $current, opcode ${instructions[current]} (requires $required value(s), has $depth)';
			var nextDepth = depth + deltaByIp[current];
			if (instructions[current] == 42 && nextDepth < 0)
				nextDepth = 0;

			if (catchByIp[current] >= 0)
				enqueueStackFlow(catchByIp[current], depth + 1, length, starts, depths, pending);
			if (branchByIp[current] >= 0)
				enqueueStackFlow(branchByIp[current], nextDepth, length, starts, depths, pending);
			if (!terminal[current] && !unconditional[current])
				enqueueStackFlow(nextByIp[current], nextDepth, length, starts, depths, pending);
		}
	}

	static function enqueueStackFlow(target:Int, depth:Int, length:Int, starts:Array<Bool>, depths:Array<Int>, pending:Array<Int>):Void {
		if (target == length)
			return;
		if (!starts[target])
			throw 'Control flow target $target is not an instruction boundary';
		if (depths[target] >= 0) {
			if (depths[target] != depth)
				throw 'Inconsistent stack depth at instruction index $target';
			return;
		}
		depths[target] = depth;
		pending.push(target);
	}

	static function checkFunctionPrototype(idx:Int, chunk:BytecodeChunk):Void {
		checkConstIndex(idx, chunk);
		var proto = chunk.constants[idx];
		if (proto == null || !Reflect.isObject(proto) || !Reflect.hasField(proto, "args") || !Std.isOfType(Reflect.field(proto, "args"), Array)
				|| !Reflect.hasField(proto, "bodyChunk") || !Std.isOfType(Reflect.field(proto, "bodyChunk"), BytecodeChunk))
			throw 'Constant index $idx is not a valid function prototype';
	}

	static function checkCatchClause(idx:Int, chunk:BytecodeChunk):Void {
		checkConstIndex(idx, chunk);
		var clause = chunk.constants[idx];
		if (clause == null || !Reflect.isObject(clause) || !Reflect.hasField(clause, "pattern"))
			throw 'Constant index $idx is not a valid catch clause';
		var pattern = Reflect.field(clause, "pattern");
		if (pattern == null || !Reflect.hasField(pattern, "def") || !Reflect.hasField(pattern, "pos"))
			throw 'Constant index $idx has an invalid catch pattern';
	}

	static function checkChunkConst(idx:Int, chunk:BytecodeChunk, label:String):Void {
		checkConstIndex(idx, chunk);
		if (!Std.isOfType(chunk.constants[idx], BytecodeChunk))
			throw 'Constant index $idx is not a valid $label bytecode chunk';
	}

	static function checkExprConst(idx:Int, chunk:BytecodeChunk, label:String):Void {
		checkConstIndex(idx, chunk);
		var value = chunk.constants[idx];
		if (value == null || !Reflect.isObject(value) || !Reflect.hasField(value, "def") || !Reflect.hasField(value, "pos"))
			throw 'Constant index $idx is not a valid $label expression';
	}

	static function checkStringConst(idx:Int, chunk:BytecodeChunk, label:String):Void {
		checkConstIndex(idx, chunk);
		if (!Std.isOfType(chunk.constants[idx], String))
			throw 'Constant index $idx is not a valid $label string';
	}

	static inline function checkOperands(ip:Int, count:Int, length:Int):Void {
		if (count < 0)
			throw 'Invalid negative operand count $count at instruction index $ip';
		if (count > length - ip)
			throw 'Unexpected end of instructions: missing $count operand(s) at instruction index $ip';
	}

	static inline function checkNonNegative(value:Int, label:String, ip:Int):Void {
		if (value < 0)
			throw 'Invalid negative $label $value at instruction index $ip';
	}

	static inline function checkConstIndex(idx:Int, chunk:BytecodeChunk):Void {
		if (idx < 0 || idx >= chunk.constants.length)
			throw 'Constant index $idx out of bounds';
	}

	static inline function checkSlotIndex(slot:Int, chunk:BytecodeChunk):Void {
		if (slot < 0 || slot >= chunk.maxSlots)
			throw 'Local slot index $slot out of bounds (maxSlots = ${chunk.maxSlots})';
	}

	static inline function checkJumpRange(target:Int, length:Int):Void {
		if (target < 0 || target > length)
			throw 'Jump target $target out of bounds (instructions length = $length)';
	}

	static function checkJumpBoundary(source:Int, target:Int, length:Int, starts:Array<Bool>):Void {
		if (target != length && !starts[target])
			throw 'Jump target $target at instruction index $source is not an instruction boundary';
	}
}
