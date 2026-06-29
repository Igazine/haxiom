package haxiom;

import haxiom.VM.BytecodeChunk;

class BytecodeVerifier {
    public static function verify(chunk:BytecodeChunk):Void {
        if (chunk == null) {
            throw "Cannot verify null bytecode chunk";
        }
        
        // 1. Verify constant pool elements recursively
        if (chunk.constants != null) {
            for (c in chunk.constants) {
                if (c != null && Reflect.hasField(c, "bodyChunk")) {
                    var body = Reflect.field(c, "bodyChunk");
                    if (body != null && Std.isOfType(body, BytecodeChunk)) {
                        verify(cast body);
                    }
                }
            }
        }
        
        var inst = chunk.instructions;
        if (inst == null) {
            throw "Instructions array is null";
        }
        
        var ip = 0;
        while (ip < inst.length) {
            var op:Int = inst[ip++];
            if (op < 0 || op > 74) {
                throw 'Invalid opcode $op at instruction index ${ip - 1}';
            }
            
            // Check operands based on Opcode enum values
            switch (op) {
                case 1: // OP_LOAD_CONST
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk);
                    
                case 2, 3: // OP_GET_LOCAL, OP_SET_LOCAL
                    checkOperands(ip, 1, inst.length);
                    checkSlotIndex(inst[ip++], chunk);
                    
                case 4, 5: // OP_GET_VAR, OP_SET_VAR
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk);
                    
                case 6: // OP_DECLARE_VAR
                    checkOperands(ip, 3, inst.length);
                    checkConstIndex(inst[ip++], chunk); // name
                    var typeIdx = inst[ip++];
                    if (typeIdx >= 0) checkConstIndex(typeIdx, chunk);
                    ip++; // isFinal (0 or 1)
                    
                case 28, 29, 30, 31, 32: // OP_JUMP, OP_JUMP_IF_FALSE, OP_JUMP_IF_FALSE_PEEK, OP_JUMP_IF_TRUE_PEEK, OP_JUMP_IF_NOT_NULL_PEEK
                    checkOperands(ip, 1, inst.length);
                    checkJumpTarget(inst[ip++], inst.length);
                    
                case 33: // OP_CALL
                    checkOperands(ip, 1, inst.length);
                    ip++; // numArgs
                    
                case 35, 36, 57, 58: // OP_GET_FIELD, OP_SET_FIELD, OP_SAFE_GET_FIELD, OP_SAFE_SET_FIELD
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // field name
                    
                case 37, 70: // OP_NEW_ARRAY, OP_NEW_MAP
                    checkOperands(ip, 1, inst.length);
                    ip++; // length
                    
                case 38: // OP_NEW_OBJECT
                    checkOperands(ip, 1, inst.length);
                    var fieldCount = inst[ip++];
                    checkOperands(ip, fieldCount, inst.length);
                    for (i in 0...fieldCount) {
                        checkConstIndex(inst[ip++], chunk);
                    }
                    
                case 41: // OP_MAKE_FUNCTION
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // proto
                    
                case 48: // OP_PUSH_TRY
                    checkOperands(ip, 1, inst.length);
                    checkJumpTarget(inst[ip++], inst.length); // catchIp
                    
                case 50: // OP_MATCH_CASE
                    checkOperands(ip, 2, inst.length);
                    checkConstIndex(inst[ip++], chunk); // pattern
                    var guardIdx = inst[ip++];
                    if (guardIdx >= 0) checkConstIndex(guardIdx, chunk);
                    
                case 51: // OP_MATCH_CATCH
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // catch clause object
                    
                case 52: // OP_UNOP
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // op string
                    
                case 53: // OP_UNOP_MUTATE
                    checkOperands(ip, 2, inst.length);
                    checkConstIndex(inst[ip++], chunk); // op string
                    checkConstIndex(inst[ip++], chunk); // expr
                    
                case 56: // OP_NEW
                    checkOperands(ip, 2, inst.length);
                    checkConstIndex(inst[ip++], chunk); // type
                    ip++; // numArgs
                    
                case 59: // OP_CAST
                    checkOperands(ip, 1, inst.length);
                    var typeIdx = inst[ip++];
                    if (typeIdx >= 0) checkConstIndex(typeIdx, chunk);
                    
                case 60, 61, 62, 63, 64, 65, 66, 67: // OP_DECLARE_CLASS to OP_PACKAGE
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // AST node
                    
                case 69: // OP_CALL_METHOD
                    checkOperands(ip, 2, inst.length);
                    checkConstIndex(inst[ip++], chunk); // method name
                    ip++; // numArgs
                    
                case 72: // OP_PUSH_CASE_SCOPE
                    // 0 operands
                    
                case 73: // OP_CHECK_TYPE
                    checkOperands(ip, 1, inst.length);
                    checkConstIndex(inst[ip++], chunk); // type
                    
                case 74: // OP_AWAIT
                    // 0 operands
                    
                case 75: // OP_EREG
                    checkOperands(ip, 2, inst.length);
                    checkConstIndex(inst[ip++], chunk); // pattern
                    checkConstIndex(inst[ip++], chunk); // flags
                    
                default:
                    // Opcodes with 0 operands
                    // OP_NOP, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_EQ, OP_NEQ, OP_LT, OP_LTE, OP_GT, OP_GTE, OP_AND, OP_OR, OP_NOT, OP_BIT_AND, OP_BIT_OR, OP_BIT_XOR, OP_BIT_NOT, OP_SHL, OP_SHR, OP_USHR, OP_RETURN, OP_THROW, OP_GET_THIS, OP_POP, OP_PUSH_SCOPE, OP_POP_SCOPE, OP_GET_ITERATOR, OP_ITERATOR_HAS_NEXT, OP_ITERATOR_NEXT, OP_POP_TRY, OP_ARRAY_ACCESS_GET, OP_ARRAY_ACCESS_SET, OP_DUP, OP_RANGE, OP_AWAIT
            }
        }
    }

    private static inline function checkOperands(ip:Int, count:Int, length:Int) {
        if (ip + count > length) {
            throw 'Unexpected end of instructions: missing $count operand(s) at instruction index $ip';
        }
    }

    private static inline function checkConstIndex(idx:Int, chunk:BytecodeChunk) {
        if (idx < 0 || idx >= chunk.constants.length) {
            throw 'Constant index $idx out of bounds';
        }
    }

    private static inline function checkSlotIndex(slot:Int, chunk:BytecodeChunk) {
        if (slot < 0 || slot >= chunk.maxSlots) {
            throw 'Local slot index $slot out of bounds (maxSlots = ${chunk.maxSlots})';
        }
    }

    private static inline function checkJumpTarget(target:Int, length:Int) {
        if (target < 0 || target > length) {
            throw 'Jump target $target out of bounds (instructions length = $length)';
        }
    }
}
