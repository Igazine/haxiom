package haxiom;

import haxiom.AST;
import haxiom.Interp;
import haxe.DynamicAccess;

enum abstract Opcode(Int) from Int to Int {
    var OP_NOP = 0;
    var OP_LOAD_CONST = 1;
    var OP_GET_LOCAL = 2;
    var OP_SET_LOCAL = 3;
    var OP_GET_VAR = 4;
    var OP_SET_VAR = 5;
    var OP_DECLARE_VAR = 6;
    var OP_ADD = 7;
    var OP_SUB = 8;
    var OP_MUL = 9;
    var OP_DIV = 10;
    var OP_MOD = 11;
    var OP_EQ = 12;
    var OP_NEQ = 13;
    var OP_LT = 14;
    var OP_LTE = 15;
    var OP_GT = 16;
    var OP_GTE = 17;
    var OP_AND = 18;
    var OP_OR = 19;
    var OP_NOT = 20;
    var OP_BIT_AND = 21;
    var OP_BIT_OR = 22;
    var OP_BIT_XOR = 23;
    var OP_BIT_NOT = 24;
    var OP_SHL = 25;
    var OP_SHR = 26;
    var OP_USHR = 27;
    var OP_JUMP = 28;
    var OP_JUMP_IF_FALSE = 29;
    var OP_JUMP_IF_FALSE_PEEK = 30;
    var OP_JUMP_IF_TRUE_PEEK = 31;
    var OP_JUMP_IF_NOT_NULL_PEEK = 32;
    var OP_CALL = 33;
    var OP_RETURN = 34;
    var OP_GET_FIELD = 35;
    var OP_SET_FIELD = 36;
    var OP_NEW_ARRAY = 37;
    var OP_NEW_OBJECT = 38;
    var OP_THROW = 39;
    var OP_GET_THIS = 40;
    var OP_MAKE_FUNCTION = 41;
    var OP_POP = 42;
    var OP_PUSH_SCOPE = 43;
    var OP_POP_SCOPE = 44;
    var OP_GET_ITERATOR = 45;
    var OP_ITERATOR_HAS_NEXT = 46;
    var OP_ITERATOR_NEXT = 47;
    var OP_PUSH_TRY = 48;
    var OP_POP_TRY = 49;
    var OP_MATCH_CASE = 50;
    var OP_MATCH_CATCH = 51;
    var OP_UNOP = 52;
    var OP_UNOP_MUTATE = 53;
    var OP_ARRAY_ACCESS_GET = 54;
    var OP_ARRAY_ACCESS_SET = 55;
    var OP_NEW = 56;
    var OP_SAFE_GET_FIELD = 57;
    var OP_SAFE_SET_FIELD = 58;
    var OP_CAST = 59;
    var OP_DECLARE_CLASS = 60;
    var OP_DECLARE_INTERFACE = 61;
    var OP_DECLARE_ENUM = 62;
    var OP_DECLARE_ABSTRACT = 63;
    var OP_DECLARE_TYPEDEF = 64;
    var OP_IMPORT = 65;
    var OP_USING = 66;
    var OP_PACKAGE = 67;
    var OP_DUP = 68;
    var OP_CALL_METHOD = 69;
    var OP_NEW_MAP = 70;
    var OP_RANGE = 71;
    var OP_PUSH_CASE_SCOPE = 72;
    var OP_CHECK_TYPE = 73;
    var OP_AWAIT = 74;
    var OP_EREG = 75;
}

typedef DebugSymbol = {
    var name:String;
    var slot:Int;
    var startIp:Int;
    var endIp:Int;
}

@:keep
class InlineCacheEntry {
    public var lastClass:Dynamic = null;
    public var lastObject:Dynamic = null;
    public var cachedValue:Dynamic = null;
    public var isNormalField:Bool = false;
    public var isMethod:Bool = false;
    public var isProperty:Bool = false;
    public var isNativeProperty:Bool = false;
    public var fieldName:String = null;
    
    // For methods:
    public var cachedMethodDef:Dynamic = null;
    
    // For getters / setters:
    public var getterMethod:Dynamic = null;
    public var setterMethod:Dynamic = null;

    // Megamorphic fallback:
    public var isMegamorphic:Bool = false;

    // Linked list next pointer:
    public var next:InlineCacheEntry = null;

    public function new() {}
}

@:keep
class BytecodeChunk {
    public var inlineCaches:Map<Int, InlineCacheEntry> = new Map();
    public var instructions:Array<Int>;
    public var constants:Array<Dynamic>;
    public var positions:Array<Pos>;
    public var maxSlots:Int;
    public var isAsync:Bool;
    public var debugSymbols:Null<Array<DebugSymbol>>;

    public function new(instructions:Array<Int>, constants:Array<Dynamic>, positions:Array<Pos>, ?maxSlots:Int = 0, ?isAsync:Bool = false, ?debugSymbols:Null<Array<DebugSymbol>> = null) {
        this.instructions = instructions;
        this.constants = constants;
        this.positions = positions;
        this.maxSlots = maxSlots;
        this.isAsync = isAsync;
        this.debugSymbols = debugSymbols;
    }

    public function getActiveLocalsAt(ip:Int):Map<Int, String> {
        var active = new Map<Int, String>();
        if (debugSymbols == null) return active;
        for (sym in debugSymbols) {
            if (ip >= sym.startIp && ip <= sym.endIp) {
                active.set(sym.slot, sym.name);
            }
        }
        return active;
    }

    public function getBytes(?key:haxiom.HXBCKey):haxe.io.Bytes {
        return haxiom.Serializer.serializeBytecode(this, key);
    }

    public static function fromBytes(bytes:haxe.io.Bytes, ?key:haxiom.HXBCKey):BytecodeChunk {
        return haxiom.Serializer.deserializeBytecode(bytes, key);
    }
}

class VMCallFrame {
    public var chunk:BytecodeChunk;
    public var ip:Int;
    public var scope:Scope;
    public var methodName:String;
    public var tryStack:Array<{catchIp:Int, stackSize:Int, scope:Scope}> = [];
    public var locals:Array<Dynamic> = [];
    public var isInPool:Bool = false;

    public function new(chunk:BytecodeChunk, ip:Int, scope:Scope, ?methodName:String = "") {
        this.chunk = chunk;
        this.ip = ip;
        this.scope = scope;
        this.methodName = methodName;
        this.locals = [for (i in 0...chunk.maxSlots) null];
    }
}

class VM {
    public static var enablePooling:Bool = true;
    static var framePool:Array<VMCallFrame> = [];
    static var stackPool:Array<Array<Dynamic>> = [];
    static var callFramesPool:Array<Array<VMCallFrame>> = [];

    public static inline function isTruthy(v:Dynamic):Bool {
        return v != null && v != false;
    }

    public static function obtainFrame(chunk:BytecodeChunk, ip:Int, scope:Scope, methodName:String):VMCallFrame {
        var frame:VMCallFrame = null;
        if (enablePooling && framePool.length > 0) {
            frame = framePool.pop();
            frame.isInPool = false;
            frame.chunk = chunk;
            frame.ip = ip;
            frame.scope = scope;
            frame.methodName = methodName;
            #if haxe4
            frame.tryStack.resize(0);
            #else
            frame.tryStack = [];
            #end
            if (frame.locals.length < chunk.maxSlots) {
                frame.locals = [for (i in 0...chunk.maxSlots) null];
            } else {
                for (i in 0...chunk.maxSlots) {
                    frame.locals[i] = null;
                }
            }
        } else {
            frame = new VMCallFrame(chunk, ip, scope, methodName);
        }
        return frame;
    }

    public static function recycleFrame(frame:VMCallFrame):Void {
        if (frame == null) return;
        if (!enablePooling) return;
        if (frame.isInPool) return;

        if (frame.chunk != null) {
            var slots = frame.chunk.maxSlots;
            var len = frame.locals.length;
            var limit = slots < len ? slots : len;
            for (i in 0...limit) {
                frame.locals[i] = null;
            }
        } else {
            for (i in 0...frame.locals.length) {
                frame.locals[i] = null;
            }
        }

        frame.chunk = null;
        frame.scope = null;
        frame.methodName = null;
        #if haxe4
        frame.tryStack.resize(0);
        #else
        frame.tryStack = [];
        #end
        frame.isInPool = true;
        framePool.push(frame);
    }

    public static function runChunk(interp:Interp, chunk:BytecodeChunk, scope:Scope, ?currentThis:Dynamic, ?methodName:String = "toplevel", ?args:Array<Dynamic>):Dynamic {
        if (chunk.isAsync) {
            var fiber = new VMFiber();
            fiber.scope = scope;
            fiber.thisContext = currentThis;
            executeLoop(interp, fiber, chunk, scope, currentThis, methodName, args);
            return fiber.future;
        }
        return executeLoop(interp, null, chunk, scope, currentThis, methodName, args);
    }

    public static function executeLoop(interp:Interp, fiber:Null<VMFiber>, chunk:Null<BytecodeChunk>, scope:Null<Scope>, ?currentThis:Dynamic, ?methodName:String = "toplevel", ?args:Array<Dynamic>):Dynamic {
        var stack:Array<Dynamic> = null;
        var callFrames:Array<VMCallFrame> = null;
        var isResumption = (fiber != null && fiber.callFrames.length > 0);
        
        if (isResumption) {
            stack = fiber.stack;
            callFrames = fiber.callFrames;
            interp.currentThis = fiber.thisContext;
        } else {
            if (enablePooling) {
                stack = stackPool.length > 0 ? stackPool.pop() : [];
                callFrames = callFramesPool.length > 0 ? callFramesPool.pop() : [];
            } else {
                stack = [];
                callFrames = [];
            }
            var frame = obtainFrame(chunk, 0, scope, methodName);
            if (args != null) {
                for (i in 0...args.length) {
                    if (i < frame.locals.length) {
                        frame.locals[i] = args[i];
                    }
                }
            }
            if (currentThis != null) {
                frame.scope.declare("this", currentThis);
            }
            callFrames.push(frame);
        }
        
        var frame = callFrames[callFrames.length - 1];
        var inst = frame.chunk.instructions;
        var consts = frame.chunk.constants;
        var posTable = frame.chunk.positions;

        inline function currentPos():Pos {
            return frame.chunk.positions[frame.ip] != null ? frame.chunk.positions[frame.ip] : { line: 1, col: 1 };
        }

        try {
            while (fiber == null || !fiber.isSuspended) {
                if (interp.maxInstructions > 0 && ++interp.instructionsCount > interp.maxInstructions) {
                    var cp = currentPos();
                    var fileInfo = cp.file != null ? cp.file : "script";
                    var lineVal = cp.line;
                    var colVal = cp.col;
                    var locationStr = 'Runtime Error: Instruction limit exceeded (${interp.maxInstructions} ops) at ' + fileInfo + ':' + lineVal + ':' + colVal;
                    var vmCallStack = [for (f in callFrames) { method: f.methodName != null ? f.methodName : "anonymous", pos: cp }];
                    throw new haxiom.ScriptException("Instruction limit exceeded (possible infinite loop)", vmCallStack, locationStr, lineVal, colVal, fileInfo);
                }
                try {
                    if (fiber != null && fiber.hasError) {
                        fiber.hasError = false;
                        var err = fiber.error;
                        fiber.error = null;
                        throw err;
                    }
                    if (frame.ip >= inst.length) {
                        if (callFrames.length > 1) {
                            var popped = callFrames.pop();
                            recycleFrame(popped);
                            frame = callFrames[callFrames.length - 1];
                            inst = frame.chunk.instructions;
                            consts = frame.chunk.constants;
                            posTable = frame.chunk.positions;
                            continue;
                        }
                        break;
                    }
                
                // Track source position in interpreter for stack traces
                var currentFramePos = frame.chunk.positions[frame.ip];
                if (currentFramePos != null) {
                    interp.lastEvalPos = currentFramePos;
                }

                var op:Opcode = inst[frame.ip++];
                switch (op) {
                    case OP_NOP:
                        // Do nothing

                    case OP_LOAD_CONST:
                        var idx = inst[frame.ip++];
                        stack.push(consts[idx]);

                    case OP_GET_LOCAL:
                        var slot = inst[frame.ip++];
                        stack.push(frame.locals[slot]);

                    case OP_SET_LOCAL:
                        var slot = inst[frame.ip++];
                        var val = stack[stack.length - 1];
                        #if haxiom_debug
                        trace('OP_SET_LOCAL slot ' + slot + ' = ' + Std.string(val));
                        #end
                        frame.locals[slot] = val;

                    case OP_GET_VAR:
                        var idx = inst[frame.ip++];
                        var name:String = consts[idx];
                        if (name == "this") {
                            stack.push(interp.currentThis);
                        } else if (name == "super") {
                            if (interp.currentThis != null && Std.isOfType(interp.currentThis, HaxiomInstance)) {
                                stack.push(new haxiom.HaxiomSuperInstance(cast interp.currentThis, interp, frame.scope));
                            } else {
                                throw "Cannot use 'super' outside of a class instance constructor or method";
                            }
                        } else {
                            var val:Dynamic = null;
                            if (!frame.scope.exists(name) && interp.currentThis != null) {
                                if (Std.isOfType(interp.currentThis, HaxiomInstance)) {
                                    val = interp.evalField(interp.currentThis, name, frame.scope, currentPos());
                                } else if (Std.isOfType(interp.currentThis, HaxiomClass)) {
                                    var cls:HaxiomClass = cast interp.currentThis;
                                    var fDef = interp.findFieldDef(cls, name);
                                    var isStaticField = fDef != null && fDef.isStatic;
                                    var isStaticMethod = interp.findStaticMethod(cls, name) != null;
                                    if (isStaticField || isStaticMethod) {
                                        val = interp.evalField(interp.currentThis, name, frame.scope, currentPos());
                                    } else {
                                        val = frame.scope.get(name);
                                    }
                                } else {
                                    val = frame.scope.get(name);
                                }
                            } else {
                                val = frame.scope.get(name);
                            }
                            #if haxiom_debug
                            trace('OP_GET_VAR: ' + name + ' = ' + Std.string(val));
                            #end
                            stack.push(val);
                        }

                    case OP_SET_VAR:
                        var idx = inst[frame.ip++];
                        var name:String = consts[idx];
                        var val = stack[stack.length - 1];
                        if (name == "this") {
                            interp.currentThis = val;
                        } else {
                            if (!frame.scope.exists(name) && interp.currentThis != null) {
                                if (Std.isOfType(interp.currentThis, HaxiomInstance)) {
                                    var inst:HaxiomInstance = cast interp.currentThis;
                                    var fDef = interp.findFieldDef(inst.cls, name);
                                    if (fDef != null && fDef.property != null && fDef.property.set == "set" && !interp.isInsideAccessor(name)) {
                                        var m = interp.findMethod(inst.cls, "set_" + name);
                                        if (m != null) {
                                            Reflect.callMethod(null, interp.bindMethod(interp.currentThis, m), [val]);
                                        }
                                    } else {
                                        if (fDef != null && fDef.isFinal && interp.currentConstructorInstance != inst) {
                                            throw 'Cannot reassign final field $name outside of constructor';
                                        }
                                        if (fDef != null && fDef.type != null) {
                                            val = interp.castOrCheckType(val, fDef.type, frame.scope, inst.genericBindings);
                                        }
                                        inst.fields.set(name, val);
                                    }
                                } else if (Std.isOfType(interp.currentThis, HaxiomClass)) {
                                    var cls:HaxiomClass = cast interp.currentThis;
                                    var fDef = interp.findFieldDef(cls, name);
                                    if (fDef != null && fDef.isStatic) {
                                        if (fDef.property != null && fDef.property.set == "set" && !interp.isInsideAccessor(name)) {
                                            var m = interp.findStaticMethod(cls, "set_" + name);
                                            if (m != null) {
                                                Reflect.callMethod(null, interp.bindMethod(interp.currentThis, m), [val]);
                                            }
                                        } else {
                                            if (fDef.isFinal) {
                                                throw 'Cannot reassign static final field $name';
                                            }
                                            if (fDef.type != null) {
                                                val = interp.castOrCheckType(val, fDef.type, frame.scope);
                                            }
                                            cls.staticFields.set(name, val);
                                        }
                                    } else {
                                        frame.scope.checkAndSet(name, val, interp);
                                    }
                                } else {
                                    frame.scope.checkAndSet(name, val, interp);
                                }
                            } else {
                                frame.scope.checkAndSet(name, val, interp);
                            }
                        }

                    case OP_DECLARE_VAR:
                        var nameIdx = inst[frame.ip++];
                        var typeIdx = inst[frame.ip++];
                        var isFinal = inst[frame.ip++];
                        var name:String = consts[nameIdx];
                        var type:TypeDecl = typeIdx >= 0 ? consts[typeIdx] : null;
                        var val = stack.pop();
                        #if haxiom_debug
                        trace('OP_DECLARE_VAR: ' + name + ' = ' + Std.string(val));
                        #end
                        if (type != null) {
                            val = interp.castOrCheckType(val, type, frame.scope);
                        }
                        frame.scope.declare(name, val, type, isFinal == 1);

                    case OP_ADD:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("+", v1, v2);
                        if (overloadRes.success) {
                            stack.push(overloadRes.value);
                        } else if (TypeSystem.isString(v1) || TypeSystem.isString(v2)) {
                            stack.push(Std.string(v1) + Std.string(v2));
                        } else {
                            stack.push((v1 + v2 : Dynamic));
                        }

                    case OP_SUB:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("-", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 - v2 : Dynamic));

                    case OP_MUL:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("*", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 * v2 : Dynamic));

                    case OP_DIV:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("/", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 / v2 : Dynamic));

                    case OP_MOD:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("%", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 % v2 : Dynamic));

                    case OP_EQ:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("==", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 == v2 : Dynamic));

                    case OP_NEQ:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("!=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 != v2 : Dynamic));

                    case OP_LT:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("<", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 < v2 : Dynamic));

                    case OP_LTE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload("<=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 <= v2 : Dynamic));

                    case OP_GT:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload(">", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 > v2 : Dynamic));

                    case OP_GTE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        var overloadRes = interp.findAbstractBinopOverload(">=", v1, v2);
                        stack.push(overloadRes.success ? overloadRes.value : (v1 >= v2 : Dynamic));

                    case OP_AND:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((v1 : Bool) && (v2 : Bool));

                    case OP_OR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((v1 : Bool) || (v2 : Bool));

                    case OP_NOT:
                        var v = stack.pop();
                        stack.push(!cast(v, Bool));

                    case OP_BIT_AND:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) & (cast v2 : Int));

                    case OP_BIT_OR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) | (cast v2 : Int));

                    case OP_BIT_XOR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) ^ (cast v2 : Int));

                    case OP_BIT_NOT:
                        var v = stack.pop();
                        stack.push(~(cast v : Int));

                    case OP_SHL:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) << (cast v2 : Int));

                    case OP_SHR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) >> (cast v2 : Int));

                    case OP_USHR:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        stack.push((cast v1 : Int) >>> (cast v2 : Int));

                    case OP_JUMP:
                        var targetIp = inst[frame.ip++];
                        frame.ip = targetIp;

                    case OP_JUMP_IF_FALSE:
                        var targetIp = inst[frame.ip++];
                        var v = stack.pop();
                        if (!VM.isTruthy(v)) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_FALSE_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (!VM.isTruthy(v)) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_TRUE_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (VM.isTruthy(v)) {
                            frame.ip = targetIp;
                        }

                    case OP_JUMP_IF_NOT_NULL_PEEK:
                        var targetIp = inst[frame.ip++];
                        var v = stack[stack.length - 1];
                        if (v != null) {
                            frame.ip = targetIp;
                        }

                    case OP_CALL:
                        var argCount = inst[frame.ip++];
                        var func = stack.pop();
                        var args:Array<Dynamic> = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }
                        
                        if (func != null && Std.isOfType(func, haxiom.HaxiomSuperInstance)) {
                            var superInst:haxiom.HaxiomSuperInstance = cast func;
                            var res = superInst.callConstructor(args);
                            stack.push(res);
                        } else {
                            var res = Reflect.callMethod(null, func, args);
                            stack.push(res);
                        }

                    case OP_RETURN:
                        var res = stack.pop();
                        if (callFrames.length > 1) {
                            var popped = callFrames.pop();
                            recycleFrame(popped);
                            frame = callFrames[callFrames.length - 1];
                            inst = frame.chunk.instructions;
                            consts = frame.chunk.constants;
                            posTable = frame.chunk.positions;
                            stack.push(res);
                        } else {
                            stack.push(res);
                            break;
                        }

                    case OP_GET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var obj = stack.pop();
                        if (obj == null) throw 'Cannot read field "$fieldName" of null';
                        if (Std.isOfType(obj, haxiom.HaxiomSuperInstance)) {
                            var superInst:haxiom.HaxiomSuperInstance = cast obj;
                            var parentCls = superInst.inst.cls.parent;
                            var m = interp.findMethod(parentCls, fieldName);
                            if (m != null) {
                                stack.push(interp.bindMethod(superInst.inst, m));
                            } else {
                                throw 'Parent method or field "$fieldName" not found on class ${superInst.inst.cls.name}';
                            }
                        } else {
                            var cacheKey = frame.ip - 2;
                            var cache = frame.chunk.inlineCaches.get(cacheKey);
                            var resolved:Dynamic = null;
                            var cacheHit = false;

                            var classKey:Dynamic = null;
                            if (Std.isOfType(obj, HaxiomInstance)) {
                                classKey = (cast obj : HaxiomInstance).cls;
                            } else {
                                classKey = Type.getClass(obj);
                                if (classKey == null && Type.typeof(obj) == TObject) {
                                    classKey = "__anonymous__";
                                }
                            }

                            if (cache != null && !cache.isMegamorphic && classKey != null) {
                                var curr = cache;
                                while (curr != null) {
                                    if (curr.lastClass == classKey) {
                                        if (curr.isNormalField) {
                                            if (Std.isOfType(obj, HaxiomInstance)) {
                                                resolved = (cast obj : HaxiomInstance).fields.get(fieldName);
                                            } else {
                                                resolved = Reflect.field(obj, fieldName);
                                            }
                                            cacheHit = true;
                                        } else if (curr.isMethod) {
                                            if (Std.isOfType(obj, HaxiomInstance)) {
                                                resolved = interp.bindMethod(cast obj, curr.cachedMethodDef);
                                            } else {
                                                resolved = Reflect.field(obj, fieldName);
                                            }
                                            cacheHit = true;
                                        } else if (curr.isProperty) {
                                            if (curr.isNativeProperty) {
                                                resolved = Reflect.getProperty(obj, fieldName);
                                            } else {
                                                if (curr.getterMethod != null) {
                                                    resolved = Reflect.callMethod(null, interp.bindMethod(obj, curr.getterMethod), []);
                                                } else {
                                                    resolved = null;
                                                }
                                            }
                                            cacheHit = true;
                                        }
                                        break;
                                    }
                                    curr = curr.next;
                                }
                            }

                            if (cacheHit) {
                                stack.push(resolved);
                            } else {
                                var val = interp.evalField(obj, fieldName, frame.scope, currentPos());
                                stack.push(val);

                                if (classKey != null) {
                                    var newEntry = new InlineCacheEntry();
                                    newEntry.lastClass = classKey;
                                    newEntry.fieldName = fieldName;

                                    if (Std.isOfType(obj, HaxiomInstance)) {
                                        var instObj:HaxiomInstance = cast obj;
                                        var fDef = interp.findFieldDef(instObj.cls, fieldName);
                                        if (fDef != null) {
                                            if (fDef.property != null) {
                                                newEntry.isProperty = true;
                                                var getAccessor = fDef.property.get;
                                                if (getAccessor == "get") {
                                                    newEntry.getterMethod = interp.findMethod(instObj.cls, "get_" + fieldName);
                                                }
                                            } else if (fDef.isMethod) {
                                                newEntry.isMethod = true;
                                                newEntry.cachedMethodDef = interp.findMethod(instObj.cls, fieldName);
                                            } else {
                                                newEntry.isNormalField = true;
                                            }
                                        } else {
                                            newEntry.isNormalField = true;
                                        }
                                    } else {
                                        if (Reflect.isFunction(val)) {
                                            newEntry.isMethod = true;
                                        } else {
                                            if (Reflect.hasField(obj, fieldName)) {
                                                newEntry.isNormalField = true;
                                            } else {
                                                newEntry.isProperty = true;
                                                newEntry.isNativeProperty = true;
                                            }
                                        }
                                    }

                                    if (cache == null) {
                                        frame.chunk.inlineCaches.set(cacheKey, newEntry);
                                    } else if (!cache.isMegamorphic) {
                                        var size = 1;
                                        var curr = cache;
                                        while (curr.next != null) {
                                            size++;
                                            curr = curr.next;
                                        }
                                        if (size < 4) {
                                            curr.next = newEntry;
                                        } else {
                                            cache.isMegamorphic = true;
                                        }
                                    }
                                }
                            }
                        }

                    case OP_SET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var val = stack.pop();
                        var obj = stack.pop();
                        if (obj == null) throw 'Cannot write field "$fieldName" of null';
                        if (Std.isOfType(obj, haxiom.HaxiomSuperInstance)) {
                            var superInst:haxiom.HaxiomSuperInstance = cast obj;
                            superInst.inst.fields.set(fieldName, val);
                            stack.push(val);
                        } else {
                            var cacheKey = frame.ip - 2;
                            var cache = frame.chunk.inlineCaches.get(cacheKey);
                            var cacheHit = false;

                            var classKey:Dynamic = null;
                            if (Std.isOfType(obj, HaxiomInstance)) {
                                classKey = (cast obj : HaxiomInstance).cls;
                            } else {
                                classKey = Type.getClass(obj);
                                if (classKey == null && Type.typeof(obj) == TObject) {
                                    classKey = "__anonymous__";
                                }
                            }

                            if (cache != null && !cache.isMegamorphic && classKey != null) {
                                var curr = cache;
                                while (curr != null) {
                                    if (curr.lastClass == classKey) {
                                        if (curr.isNormalField) {
                                            if (Std.isOfType(obj, HaxiomInstance)) {
                                                if (!(cast obj : HaxiomInstance).fields.exists(fieldName)) interp.trackMemory(1);
                                                (cast obj : HaxiomInstance).fields.set(fieldName, val);
                                            } else {
                                                Reflect.setField(obj, fieldName, val);
                                            }
                                            cacheHit = true;
                                        } else if (curr.isProperty) {
                                            if (curr.isNativeProperty) {
                                                Reflect.setProperty(obj, fieldName, val);
                                            } else {
                                                if (curr.setterMethod != null) {
                                                    Reflect.callMethod(null, interp.bindMethod(obj, curr.setterMethod), [val]);
                                                }
                                            }
                                            cacheHit = true;
                                        }
                                        break;
                                    }
                                    curr = curr.next;
                                }
                            }

                            if (cacheHit) {
                                stack.push(val);
                            } else {
                                var result = interp.assignField(obj, fieldName, val, frame.scope);
                                stack.push(result);

                                if (classKey != null) {
                                    var newEntry = new InlineCacheEntry();
                                    newEntry.lastClass = classKey;
                                    newEntry.fieldName = fieldName;

                                    if (Std.isOfType(obj, HaxiomInstance)) {
                                        var instObj:HaxiomInstance = cast obj;
                                        var fDef = interp.findFieldDef(instObj.cls, fieldName);
                                        if (fDef != null) {
                                            if (fDef.property != null) {
                                                newEntry.isProperty = true;
                                                var setAccessor = fDef.property.set;
                                                if (setAccessor == "set") {
                                                    newEntry.setterMethod = interp.findMethod(instObj.cls, "set_" + fieldName);
                                                }
                                            } else {
                                                newEntry.isNormalField = true;
                                            }
                                        } else {
                                            newEntry.isNormalField = true;
                                        }
                                    } else {
                                        if (Reflect.hasField(obj, fieldName)) {
                                            newEntry.isNormalField = true;
                                        } else {
                                            newEntry.isProperty = true;
                                            newEntry.isNativeProperty = true;
                                        }
                                    }

                                    if (cache == null) {
                                        frame.chunk.inlineCaches.set(cacheKey, newEntry);
                                    } else if (!cache.isMegamorphic) {
                                        var size = 1;
                                        var curr = cache;
                                        while (curr.next != null) {
                                            size++;
                                            curr = curr.next;
                                        }
                                        if (size < 4) {
                                            curr.next = newEntry;
                                        } else {
                                            cache.isMegamorphic = true;
                                        }
                                    }
                                }
                            }
                        }

                    case OP_SAFE_GET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var obj = stack.pop();
                        if (obj == null) {
                            stack.push(null);
                        } else {
                            var cacheKey = frame.ip - 2;
                            var cache = frame.chunk.inlineCaches.get(cacheKey);
                            var resolved:Dynamic = null;
                            var cacheHit = false;
                            
                            if (cache != null && cache.isMethod) {
                                if (obj == cache.lastObject) {
                                    resolved = cache.cachedValue;
                                    cacheHit = true;
                                } else if (Std.isOfType(obj, HaxiomInstance)) {
                                    var instObj:HaxiomInstance = cast obj;
                                    if (instObj.cls == cache.lastClass) {
                                        resolved = interp.bindMethod(instObj, cache.cachedMethodDef);
                                        cache.lastObject = instObj;
                                        cache.cachedValue = resolved;
                                        cacheHit = true;
                                    }
                                }
                            }
                            
                            if (cacheHit) {
                                stack.push(resolved);
                            } else {
                                var val = interp.evalField(obj, fieldName, frame.scope, currentPos());
                                stack.push(val);
                                
                                if (val != null && Reflect.isFunction(val)) {
                                    var newCache = new InlineCacheEntry();
                                    newCache.lastObject = obj;
                                    newCache.cachedValue = val;
                                    newCache.isMethod = true;
                                    if (Std.isOfType(obj, HaxiomInstance)) {
                                        var instObj:HaxiomInstance = cast obj;
                                        newCache.lastClass = instObj.cls;
                                        newCache.cachedMethodDef = interp.findMethod(instObj.cls, fieldName);
                                    } else {
                                        newCache.lastClass = Type.getClass(obj);
                                    }
                                    frame.chunk.inlineCaches.set(cacheKey, newCache);
                                }
                            }
                        }

                    case OP_SAFE_SET_FIELD:
                        var idx = inst[frame.ip++];
                        var fieldName:String = consts[idx];
                        var val = stack.pop();
                        var obj = stack.pop();
                        if (obj == null) {
                            stack.push(null);
                        } else {
                            stack.push(interp.assignField(obj, fieldName, val, frame.scope));
                        }

                    case OP_NEW_ARRAY:
                        var size = inst[frame.ip++];
                        var arr = [];
                        for (i in 0...size) {
                            arr.unshift(stack.pop());
                        }
                        var cp = currentPos();
                        var vmCallStack = [for (f in callFrames) { method: f.methodName != null ? f.methodName : "anonymous", pos: cp }];
                        interp.trackNewAllocation(arr, cp, vmCallStack);
                        stack.push(arr);

                    case OP_NEW_OBJECT:
                        var fieldCount = inst[frame.ip++];
                        var obj:DynamicAccess<Dynamic> = {};
                        var fields = [];
                        for (i in 0...fieldCount) {
                            var val = stack.pop();
                            var nameIdx = inst[frame.ip++];
                            var name:String = consts[nameIdx];
                            fields.push({ name: name, val: val });
                        }
                        for (f in fields) {
                            obj.set(f.name, f.val);
                        }
                        var cp = currentPos();
                        var vmCallStack = [for (f in callFrames) { method: f.methodName != null ? f.methodName : "anonymous", pos: cp }];
                        interp.trackNewAllocation(obj, cp, vmCallStack);
                        stack.push(obj);

                    case OP_THROW:
                        var val = stack.pop();
                        throw val;

                    case OP_GET_THIS:
                        stack.push(interp.currentThis);

                    case OP_MAKE_FUNCTION:
                        var protoIdx = inst[frame.ip++];
                        var proto = consts[protoIdx];
                        var closureScope = frame.scope;
                        closureScope.markCaptured();
                        var creationPos = currentPos();
                        
                        var func = (callArgs:Array<Dynamic>) -> {
                            #if haxiom_debug
                            trace('VM guest function invoked! callArgs=' + callArgs);
                            #end
                            var fScope = Scope.create(closureScope);
                            var mappedArgs = [];
                            for (i in 0...proto.args.length) {
                                var arg = proto.args[i];
                                var val:Dynamic = null;
                                if (arg.isRest) {
                                    val = callArgs.slice(i);
                                    if (arg.type != null) {
                                        var arr:Array<Dynamic> = cast val;
                                        for (j in 0...arr.length) {
                                            arr[j] = interp.castOrCheckType(arr[j], arg.type, fScope);
                                        }
                                    }
                                } else {
                                    val = i < callArgs.length ? callArgs[i] : null;
                                    val = interp.castOrCheckType(val, arg.type, fScope);
                                }
                                fScope.declare(arg.name, val, arg.type);
                                mappedArgs.push(val);
                            }
                            
                            interp.pushFrame(proto.name != null ? proto.name : "anonymous", creationPos);
                            try {
                                var res = VM.runChunk(interp, proto.bodyChunk, fScope, interp.currentThis, proto.name != null ? proto.name : "anonymous", mappedArgs);
                                if (proto.retType != null && interp.typeToString(proto.retType) == "Void") {
                                    res = null;
                                } else {
                                    res = interp.castOrCheckType(res, proto.retType, fScope);
                                }
                                interp.popFrame();
                                Scope.recycle(fScope);
                                return res;
                            } catch (flow:ControlFlow) {
                                interp.popFrame();
                                switch (flow) {
                                    case Return(val):
                                        if (proto.retType != null && interp.typeToString(proto.retType) == "Void") {
                                            Scope.recycle(fScope);
                                            return null;
                                        }
                                        val = interp.castOrCheckType(val, proto.retType, fScope);
                                        Scope.recycle(fScope);
                                        return val;
                                    default:
                                        Scope.recycle(fScope);
                                        throw flow;
                                }
                            } catch (err:Dynamic) {
                                interp.popFrame();
                                Scope.recycle(fScope);
                                throw err;
                            }
                        };
                        
                        var hasRest = false;
                        for (arg in proto.args) {
                            if (arg.isRest) {
                                hasRest = true;
                                break;
                            }
                        }
                        var boundFunc:Dynamic = null;
                        #if (cpp || hl || java || cs)
                        boundFunc = Reflect.makeVarArgs(func);
                        #else
                        if (hasRest) {
                            boundFunc = Reflect.makeVarArgs(func);
                        } else {
                            boundFunc = switch (proto.args.length) {
                                case 0: () -> func([]);
                                case 1: (a) -> func([a]);
                                case 2: (a, b) -> func([a, b]);
                                case 3: (a, b, c) -> func([a, b, c]);
                                case 4: (a, b, c, d) -> func([a, b, c, d]);
                                default: Reflect.makeVarArgs(func);
                            };
                        }
                        #end
                        
                        var signatureArgs = [];
                        for (arg in proto.args) {
                            var t = arg.type != null ? arg.type : TPath(["Dynamic"], []);
                            signatureArgs.push(t);
                        }
                        var signatureRet = proto.retType != null ? proto.retType : TPath(["Dynamic"], []);
                        interp.functionSignatures.set(boundFunc, TFun(signatureArgs, signatureRet));
                        
                        if (proto.name != null) {
                            frame.scope.declare(proto.name, boundFunc);
                        }
                        stack.push(boundFunc);

                    case OP_POP:
                        stack.pop();

                    case OP_PUSH_SCOPE:
                        frame.scope = Scope.create(frame.scope);

                    case OP_PUSH_CASE_SCOPE:
                        var caseScope:Scope = stack.pop();
                        frame.scope = caseScope;

                    case OP_POP_SCOPE:
                        var s = frame.scope;
                        frame.scope = s.parent;
                        Scope.recycle(s);

                     case OP_GET_ITERATOR:
                        var iterable = stack.pop();
                        var iterator:Dynamic = null;
                        if (iterable != null) {
                            if (Std.isOfType(iterable, Array)) {
                                iterator = (cast iterable : Array<Dynamic>).iterator();
                            } else if (Std.isOfType(iterable, haxe.Constraints.IMap)) {
                                iterator = (cast iterable : haxe.Constraints.IMap<Dynamic, Dynamic>).iterator();
                            } else if (Std.isOfType(iterable, IntIterator)) {
                                iterator = iterable;
                            } else {
                                var iterField = Reflect.field(iterable, "iterator");
                                if (iterField != null) {
                                    iterator = Reflect.callMethod(iterable, iterField, []);
                                } else if (Reflect.field(iterable, "hasNext") != null && Reflect.field(iterable, "next") != null) {
                                    iterator = iterable;
                                }
                            }
                        }
                        stack.push(iterator);

                    case OP_ITERATOR_HAS_NEXT:
                        var iterator = stack[stack.length - 1];
                        if (iterator != null) {
                            if (Std.isOfType(iterator, IntIterator)) {
                                stack.push((cast iterator : IntIterator).hasNext());
                            } else {
                                stack.push(Reflect.callMethod(iterator, Reflect.field(iterator, "hasNext"), []));
                            }
                        } else {
                            stack.push(false);
                        }

                    case OP_ITERATOR_NEXT:
                        var iterator = stack[stack.length - 1];
                        if (iterator != null) {
                            if (Std.isOfType(iterator, IntIterator)) {
                                stack.push((cast iterator : IntIterator).next());
                            } else {
                                stack.push(Reflect.callMethod(iterator, Reflect.field(iterator, "next"), []));
                            }
                        } else {
                            stack.push(null);
                        }

                    case OP_PUSH_TRY:
                        var catchIp = inst[frame.ip++];
                        frame.tryStack.push({ catchIp: catchIp, stackSize: stack.length, scope: frame.scope });

                    case OP_POP_TRY:
                        frame.tryStack.pop();

                    case OP_MATCH_CASE:
                        var patternIdx = inst[frame.ip++];
                        var guardIdx = inst[frame.ip++];
                        var val = stack[stack.length - 1];
                        var pattern = consts[patternIdx];
                        var guard = guardIdx >= 0 ? consts[guardIdx] : null;
                        var caseScope = Scope.create(frame.scope);
                        var matched = false;
                        try {
                            if (interp.matchPattern(val, pattern, frame.scope, caseScope)) {
                                var guardMatched = true;
                                if (guard != null) {
                                    guardMatched = interp.eval(guard, caseScope) == true;
                                }
                                if (guardMatched) {
                                    matched = true;
                                }
                            }
                        } catch (_:Dynamic) {
                            matched = false;
                        }
                        
                        if (matched) {
                            stack.pop(); // pop matched value
                            stack.push(caseScope);
                            stack.push(true);
                        } else {
                            Scope.recycle(caseScope);
                            stack.push(false);
                        }

                    case OP_MATCH_CATCH:
                        var clauseIdx = inst[frame.ip++];
                        var c = consts[clauseIdx];
                        var errVal = stack[stack.length - 1];
                        var caseScope = Scope.create(frame.scope);
                        var matched = false;
                        try {
                            if (interp.matchPattern(errVal, c.pattern, frame.scope, caseScope)) {
                                var typeMatched = true;
                                if (c.type != null) {
                                    try {
                                        errVal = interp.castOrCheckType(errVal, c.type, frame.scope);
                                        switch (c.pattern.def) {
                                            case EIdent(name):
                                                caseScope.set(name, errVal);
                                            default:
                                        }
                                    } catch (_:Dynamic) {
                                        typeMatched = false;
                                    }
                                }
                                if (typeMatched) {
                                    var guardMatched = true;
                                    if (c.guard != null) {
                                        guardMatched = interp.eval(c.guard, caseScope) == true;
                                    }
                                    if (guardMatched) {
                                        matched = true;
                                    }
                                }
                            }
                        } catch (_:Dynamic) {
                            matched = false;
                        }

                        if (matched) {
                            stack.pop(); // pop exception
                            stack.push(caseScope);
                            stack.push(true);
                        } else {
                            Scope.recycle(caseScope);
                            stack.push(false);
                        }

                    case OP_UNOP:
                        var opStr:String = consts[inst[frame.ip++]];
                        var val = stack.pop();
                        var overloadRes = interp.findAbstractUnopOverload(opStr, val);
                        if (overloadRes.success) {
                            stack.push(overloadRes.value);
                        } else {
                            var unopRes:Dynamic = null;
                            switch (opStr) {
                                case "!": unopRes = !(cast val : Bool);
                                case "-": unopRes = -(cast val : Float);
                                case "~": unopRes = ~(cast val : Int);
                                default: throw 'Unknown unary operator "$opStr"';
                            }
                            stack.push(unopRes);
                        }

                    case OP_UNOP_MUTATE:
                        var opStr:String = consts[inst[frame.ip++]];
                        var targetExprIdx = inst[frame.ip++];
                        var targetExpr = consts[targetExprIdx];
                        
                        var val = interp.eval(targetExpr, frame.scope);
                        var overloadRes = interp.findAbstractUnopOverload(opStr, val);
                        var finalVal:Dynamic = null;
                        var retVal:Dynamic = null;

                        if (overloadRes.success) {
                            finalVal = overloadRes.value;
                            retVal = finalVal;
                            if (opStr == "post++" || opStr == "post--") {
                                retVal = val;
                            }
                            interp.assign(targetExpr, finalVal, frame.scope);
                        } else {
                            switch (opStr) {
                                case "post++":
                                    finalVal = (cast val : Float) + 1;
                                    retVal = val;
                                case "post--":
                                    finalVal = (cast val : Float) - 1;
                                    retVal = val;
                                case "++":
                                    finalVal = (cast val : Float) + 1;
                                    retVal = finalVal;
                                case "--":
                                    finalVal = (cast val : Float) - 1;
                                    retVal = finalVal;
                                default:
                                    throw 'Unknown mutating unary operator "$opStr"';
                            }
                            interp.assign(targetExpr, finalVal, frame.scope);
                        }
                        stack.push(retVal);

                    case OP_ARRAY_ACCESS_GET:
                        var idx = stack.pop();
                        var obj = stack.pop();
                        stack.push(interp.getSubscript(obj, idx));

                    case OP_ARRAY_ACCESS_SET:
                        var val = stack.pop();
                        var idx = stack.pop();
                        var obj = stack.pop();
                        interp.setSubscript(obj, idx, val);
                        stack.push(val);

                    case OP_NEW:
                        var typeIdx = inst[frame.ip++];
                        var argCount = inst[frame.ip++];
                        var type:TypeDecl = consts[typeIdx];
                        var args:Array<Dynamic> = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }

                        // Evaluate new instance using parser/interpreter helpers
                        var fakeNewExpr = { def: ENew(type, [for (a in args) { def: EValue(a), pos: currentPos() }]), pos: currentPos() };
                        var res = interp.eval(fakeNewExpr, frame.scope);
                        stack.push(res);

                    case OP_CAST:
                        var typeIdx = inst[frame.ip++];
                        var type:TypeDecl = typeIdx >= 0 ? consts[typeIdx] : null;
                        var val = stack.pop();
                        if (type != null) {
                            try {
                                val = interp.castOrCheckType(val, type, frame.scope);
                            } catch (err:Dynamic) {
                                throw 'Class cast error: expected ${interp.typeToString(type)} but got ${val}';
                            }
                        }
                        stack.push(val);

                    case OP_DECLARE_CLASS:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        // In VM mode, any method body of the class will be compiled to bytecode upon invocation
                        stack.push(res);

                    case OP_DECLARE_INTERFACE:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_ENUM:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_ABSTRACT:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DECLARE_TYPEDEF:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_IMPORT:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_USING:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_PACKAGE:
                        var exprIdx = inst[frame.ip++];
                        var res = interp.eval(consts[exprIdx], frame.scope);
                        stack.push(res);

                    case OP_DUP:
                        stack.push(stack[stack.length - 1]);

                    case OP_CALL_METHOD:
                        var fieldIdx = inst[frame.ip++];
                        var argCount = inst[frame.ip++];
                        var fieldName:String = consts[fieldIdx];
                        var obj = stack.pop();
                        
                        var args:Array<Dynamic> = [];
                        for (i in 0...argCount) {
                            args.unshift(stack.pop());
                        }

                        var cacheKey = frame.ip - 3;
                        var cache = frame.chunk.inlineCaches.get(cacheKey);
                        var boundMethod:Dynamic = null;
                        var cacheHit = false;

                        if (cache != null && cache.isMethod) {
                            if (obj == cache.lastObject) {
                                boundMethod = cache.cachedValue;
                                cacheHit = true;
                            } else if (Std.isOfType(obj, HaxiomInstance)) {
                                var instObj:HaxiomInstance = cast obj;
                                if (instObj.cls == cache.lastClass) {
                                    if (cache.cachedMethodDef != null) {
                                        boundMethod = interp.bindMethod(instObj, cache.cachedMethodDef);
                                        cache.lastObject = instObj;
                                        cache.cachedValue = boundMethod;
                                        cacheHit = true;
                                    }
                                }
                            }
                        }

                        if (cacheHit) {
                            var receiver = (cache.cachedMethodDef != null || Std.isOfType(obj, HaxiomInstance)) ? null : obj;
                            var res = Reflect.callMethod(receiver, boundMethod, args);
                            stack.push(res);
                        } else {
                            if (obj != null && Std.isOfType(obj, haxiom.HaxiomSuperInstance)) {
                                var superInst:haxiom.HaxiomSuperInstance = cast obj;
                                var parentCls = superInst.inst.cls.parent;
                                var m = interp.findMethod(parentCls, fieldName);
                                if (m != null) {
                                    var bm = interp.bindMethod(superInst.inst, m);
                                    
                                    var newCache = new InlineCacheEntry();
                                    newCache.lastObject = superInst;
                                    newCache.lastClass = parentCls;
                                    newCache.cachedMethodDef = m;
                                    newCache.cachedValue = bm;
                                    newCache.isMethod = true;
                                    frame.chunk.inlineCaches.set(cacheKey, newCache);
                                    
                                    var res = Reflect.callMethod(null, bm, args);
                                    stack.push(res);
                                    continue;
                                } else {
                                    throw 'Parent method or field "$fieldName" not found on class ${superInst.inst.cls.name}';
                                }
                            }

                            if (obj != null && Std.isOfType(obj, HaxiomInstance)) {
                                var instObj:HaxiomInstance = cast obj;
                                var m = interp.findMethod(instObj.cls, fieldName);
                                if (m != null) {
                                    boundMethod = interp.bindMethod(instObj, m);
                                    
                                    var newCache = new InlineCacheEntry();
                                    newCache.lastObject = instObj;
                                    newCache.lastClass = instObj.cls;
                                    newCache.cachedMethodDef = m;
                                    newCache.cachedValue = boundMethod;
                                    newCache.isMethod = true;
                                    frame.chunk.inlineCaches.set(cacheKey, newCache);
                                    
                                    var res = Reflect.callMethod(null, boundMethod, args);
                                    stack.push(res);
                                    continue;
                                }
                            }
                            
                            // Fallback: resolve method as a field and invoke
                            var resolvedField:Dynamic = interp.evalField(obj, fieldName, frame.scope, currentPos());
                            if (resolvedField == null || !Reflect.isFunction(resolvedField)) {
                                throw 'Method "$fieldName" not found or is not a function on object $obj';
                            }
                            var newCache = new InlineCacheEntry();
                            newCache.lastObject = obj;
                            newCache.lastClass = Type.getClass(obj);
                            newCache.cachedValue = resolvedField;
                            newCache.isMethod = true;
                            frame.chunk.inlineCaches.set(cacheKey, newCache);
                            
                            var res = Reflect.callMethod(obj, cast resolvedField, args);
                            stack.push(res);
                        }

                    case OP_NEW_MAP:
                        var size = inst[frame.ip++];
                        var map:haxe.Constraints.IMap<Dynamic, Dynamic> = null;
                        if (size == 0) {
                            map = new haxiom.DynamicMap();
                        } else {
                            var evaluated = [];
                            for (i in 0...size) {
                                var val = stack.pop();
                                var key = stack.pop();
                                evaluated.unshift({ key: key, value: val });
                            }
                            var allString = true;
                            var allInt = true;
                            for (kv in evaluated) {
                                if (!Std.isOfType(kv.key, String)) allString = false;
                                if (!Std.isOfType(kv.key, Int)) allInt = false;
                            }
                            if (allString) {
                                map = new haxe.ds.StringMap<Dynamic>();
                            } else if (allInt) {
                                map = new haxe.ds.IntMap<Dynamic>();
                            } else {
                                map = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
                            }
                            for (kv in evaluated) {
                                map.set(kv.key, kv.value);
                            }
                        }
                        var cp = currentPos();
                        var vmCallStack = [for (f in callFrames) { method: f.methodName != null ? f.methodName : "anonymous", pos: cp }];
                        interp.trackNewAllocation(map, cp, vmCallStack);
                        stack.push(map);

                    case OP_RANGE:
                        var v2 = stack.pop();
                        var v1 = stack.pop();
                        interp.checkInt(v1, "IntIterator start");
                        interp.checkInt(v2, "IntIterator end");
                        stack.push(new IntIterator(cast v1, cast v2));

                    case OP_CHECK_TYPE:
                        var typeIdx = inst[frame.ip++];
                        var type:TypeDecl = consts[typeIdx];
                        var val = stack.pop();
                        var coerced = interp.castOrCheckType(val, type, frame.scope);
                        stack.push(coerced);

                    case OP_EREG:
                        var patternIdx = inst[frame.ip++];
                        var flagsIdx = inst[frame.ip++];
                        var pattern:String = consts[patternIdx];
                        var flags:String = consts[flagsIdx];
                        stack.push(new EReg(pattern, flags));

                    case OP_AWAIT:
                        var promise = stack.pop();
                        if (isPromiseLike(promise)) {
                            if (fiber == null) {
                                throw "Haxiom.await is only allowed inside async functions (annotated with @:haxiom.async)";
                            }
                            fiber.isSuspended = true;
                            fiber.stack = stack;
                            fiber.callFrames = callFrames;
                            fiber.thisContext = interp.currentThis;
                            
                            registerAwait(promise,
                                (val) -> {
                                    fiber.stack.push(val);
                                    fiber.isSuspended = false;
                                    executeLoop(interp, fiber, null, null, null, null, null);
                                },
                                (err) -> {
                                    fiber.hasError = true;
                                    fiber.error = err;
                                    fiber.isSuspended = false;
                                    executeLoop(interp, fiber, null, null, null, null, null);
                                }
                            );
                            return null;
                        } else {
                            stack.push(promise);
                        }

                    default:
                        throw 'Unsupported opcode $op';
                }
            } catch (e:ControlFlow) {
                // Rethrow control flows like Return, Break, Continue
                throw e;
            } catch (e:Dynamic) {
                if (callFrames.length > 0 && interp.lastActiveLocals == null) {
                    var topFrame = callFrames[callFrames.length - 1];
                    if (topFrame.chunk.debugSymbols != null) {
                        var localsMap = new Map<String, Dynamic>();
                        var errIp = topFrame.ip > 0 ? topFrame.ip - 1 : 0;
                        var activeLocals = topFrame.chunk.getActiveLocalsAt(errIp);
                        for (slot in activeLocals.keys()) {
                            var name = activeLocals.get(slot);
                            if (slot >= 0 && slot < topFrame.locals.length) {
                                localsMap.set(name, topFrame.locals[slot]);
                            }
                        }
                        interp.lastActiveLocals = localsMap;
                    }
                }
                
                var foundHandler = false;
                while (callFrames.length > 0) {
                    var f = callFrames[callFrames.length - 1];
                    if (f.tryStack.length > 0) {
                        var handler = f.tryStack.pop();
                        frame = f;
                        inst = frame.chunk.instructions;
                        consts = frame.chunk.constants;
                        posTable = frame.chunk.positions;
                        
                        // Reset stack size to pre-try size, push exception, restore scope, and jump to catch
                        while (stack.length > handler.stackSize) {
                            stack.pop();
                        }
                        stack.push(e);
                        frame.scope = handler.scope;
                        frame.ip = handler.catchIp;
                        foundHandler = true;
                        interp.lastActiveLocals = null;
                        break;
                    }
                    var popped = callFrames.pop();
                    recycleFrame(popped);
                }
                if (foundHandler) {
                    continue;
                }
                throw e;
            }
        }
            var res = stack.length > 0 ? stack[stack.length - 1] : null;
            if (fiber != null) {
                if (fiber.isSuspended) {
                    return null;
                } else {
                    fiber.future.resolve(res);
                    if (fiber.scope != null) {
                        Scope.recycle(fiber.scope);
                        fiber.scope = null;
                    }
                }
            }
            for (f in callFrames) {
                recycleFrame(f);
            }
            if (enablePooling && (fiber == null || !fiber.isSuspended)) {
                #if haxe4
                stack.resize(0);
                callFrames.resize(0);
                #else
                while (stack.length > 0) stack.pop();
                while (callFrames.length > 0) callFrames.pop();
                #end
                stackPool.push(stack);
                callFramesPool.push(callFrames);
            }
            return res;
        } catch (e:Dynamic) {
            trace("VM EXECUTION ERROR: " + e + "\nVM CALLSTACK: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            #if js
            // haxe.Log.trace("executeLoop caught exception: " + e + ", stack: " + js.Syntax.code("({0} && {0}.stack ? {0}.stack : null)", e), null);
            #end
            if (fiber != null) {
                if (!fiber.isSuspended) {
                    fiber.future.reject(e);
                    if (fiber.scope != null) {
                        Scope.recycle(fiber.scope);
                        fiber.scope = null;
                    }
                }
            }
            if (fiber == null || !fiber.isSuspended) {
                for (f in callFrames) {
                    recycleFrame(f);
                }
                if (enablePooling) {
                    #if haxe4
                    stack.resize(0);
                    callFrames.resize(0);
                    #else
                    while (stack.length > 0) stack.pop();
                    while (callFrames.length > 0) callFrames.pop();
                    #end
                    stackPool.push(stack);
                    callFramesPool.push(callFrames);
                }
            }
            if (fiber == null) {
                throw e;
            } else {
                return null;
            }
        }
    }

    static function isPromiseLike(val:Dynamic):Bool {
        if (val == null) return false;
        if (Std.isOfType(val, haxiom.Future)) return true;
        return Reflect.hasField(val, "then") && Reflect.isFunction(Reflect.field(val, "then"));
    }

    static function registerAwait(val:Dynamic, onResolve:Dynamic->Void, onReject:Dynamic->Void):Void {
        var cls = Type.getClass(val);
        var clsName = cls != null ? Type.getClassName(cls) : "null";
        var hasThenField = Reflect.field(val, "then") != null;
        #if js
        var isInstance = js.Syntax.code("({0} instanceof haxiom_Future)", val);
        var ctorStr = js.Syntax.code("({0} && {0}.constructor ? {0}.constructor.toString() : 'null')", val);
        // haxe.Log.trace("DEBUG registerAwait: val=" + val + " class=" + clsName + " hasThen=" + hasThenField + " instanceof=" + isInstance + " ctor=" + ctorStr, null);
        #else
        // haxe.Log.trace("DEBUG registerAwait: val=" + val + " class=" + clsName + " hasThen=" + hasThenField, null);
        #end
        if (Std.isOfType(val, haxiom.Future)) {
            var f:haxiom.Future = cast val;
            f.then(onResolve, onReject);
        } else {
            try {
                Reflect.callMethod(val, Reflect.field(val, "then"), [onResolve, onReject]);
            } catch (e:Dynamic) {
                try {
                    Reflect.callMethod(val, Reflect.field(val, "then"), [onResolve]);
                } catch (err:Dynamic) {
                    onReject(err);
                }
            }
        }
    }
}

@:keep
class HaxiomSuperInstance {
    public var inst:HaxiomInstance;
    public var interp:Interp;
    public var scope:Scope;

    public function new(inst:HaxiomInstance, interp:Interp, scope:Scope) {
        this.inst = inst;
        this.interp = interp;
        this.scope = scope;
    }

    public function callConstructor(args:Array<Dynamic>):Dynamic {
        var parentCls = inst.cls.parent;
        if (parentCls != null) {
            var constr = interp.findMethod(parentCls, "new");
            if (constr != null) {
                var cScope = Scope.create(scope);
                cScope.declare("this", inst);
                for (i in 0...constr.args.length) {
                    var arg = constr.args[i];
                    var val = i < args.length ? args[i] : null;
                    val = interp.castOrCheckType(val, arg.type, cScope);
                    cScope.declare(arg.name, val, arg.type);
                }
                var oldThis = interp.currentThis;
                var oldConstrInst = interp.currentConstructorInstance;
                interp.currentConstructorInstance = inst;
                interp.currentThis = inst;
                try {
                    if (interp.useVM) {
                        var cDyn:Dynamic = constr;
                        if (cDyn.bytecodeChunk == null) {
                            cDyn.bytecodeChunk = haxiom.BytecodeCompiler.compile(constr.body, constr.args, false, false, interp.debugMode, "new");
                        }
                        VM.runChunk(interp, cDyn.bytecodeChunk, cScope, inst, parentCls.name + ".new", args);
                    } else {
                        interp.eval(constr.body, cScope);
                    }
                    Scope.recycle(cScope);
                } catch (flow:ControlFlow) {
                    Scope.recycle(cScope);
                    switch (flow) {
                        case Return(_):
                        default: throw flow;
                    }
                } catch (err:Dynamic) {
                    Scope.recycle(cScope);
                    throw err;
                }
                interp.currentConstructorInstance = oldConstrInst;
                interp.currentThis = oldThis;
            }
        }
        return null;
    }
}

@:keep
class VMFiber {
    public var callFrames:Array<VMCallFrame> = [];
    public var stack:Array<Dynamic> = [];
    public var future:haxiom.Future;
    public var scope:Scope = null;
    public var thisContext:Dynamic = null;
    public var isSuspended:Bool = false;
    public var hasError:Bool = false;
    public var error:Dynamic = null;

    public function new() {
        this.future = new haxiom.Future();
    }
}
