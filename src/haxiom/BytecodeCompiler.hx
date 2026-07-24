package haxiom;

import haxiom.AST;
import haxiom.VM.Opcode;
import haxiom.VM.BytecodeChunk;
import haxiom.VM.DebugSymbol;

typedef LoopContext = {
	var startLabel:Int;
	var endLabel:Int;
	var scopeDepth:Int;
}

typedef LocalVar = {
	var name:String;
	var slot:Int;
	var depth:Int;
	var type:Null<TypeDecl>;
	var ?isFinal:Bool;
}

@:allow(haxiom)
class BytecodeCompiler {
	var instructions:Array<Int> = [];
	var constants:Array<Dynamic> = [];
	var positions:Array<Pos> = [];

	var loopStack:Array<LoopContext> = [];
	var currentScopeDepth:Int = 0;

	var isTopLevel:Bool = true;
	var isAsync:Bool = false;
	var debugMode:Bool = false;
	var locals:Array<LocalVar> = [];
	var maxSlots:Int = 0;
	var capturedVars:Map<String, Bool> = new Map();
	var debugSymbols:Array<DebugSymbol> = [];
	var activeLocals:Array<{name:String, slot:Int, startIp:Int}> = [];
	var functionName:Null<String> = null;
	var args:Null<Array<FunctionArg>> = null;
	var resources:Map<String, haxe.io.Bytes> = new Map();

	function new(?args:Array<FunctionArg>, ?isTopLevel:Bool = true, ?isAsync:Bool = false, ?debugMode:Bool = false, ?functionName:String) {
		this.args = args;
		this.isTopLevel = isTopLevel;
		this.isAsync = isAsync;
		this.debugMode = debugMode;
		this.functionName = functionName;
		if (args != null && !isTopLevel) {
			for (arg in args) {
				declareLocal(arg.name, arg.type);
			}
		}
	}

	static function compile(expr:Expr, ?args:Array<FunctionArg>, ?isTopLevel:Bool = true, ?isAsync:Bool = false, ?debugMode:Bool = false,
			?functionName:String):BytecodeChunk {
		var actualAsync = isAsync || hasAwait(expr);
		var compiler = new BytecodeCompiler(args, isTopLevel, actualAsync, debugMode, functionName);
		if (!isTopLevel) {
			compiler.findCapturedVars(expr, new Map<String, Bool>(), compiler.capturedVars);
		}
		compiler.compileExpr(expr);
		if (compiler.debugMode) {
			compiler.closeAllActiveLocals();
		}
		var resMap = [for (k in compiler.resources.keys()) k].length > 0 ? compiler.resources : null;
		var chunk = new BytecodeChunk(compiler.instructions, compiler.constants, compiler.debugMode ? compiler.positions : [], compiler.maxSlots,
			compiler.isAsync, compiler.debugMode ? compiler.debugSymbols : null, resMap);
		optimizeChunk(chunk);
		if (!debugMode) {
			stripPositionsFromChunk(chunk);
		}
		return chunk;
	}

	function declareLocal(name:String, type:Null<TypeDecl>, ?isFinal:Bool = false):LocalVar {
		var slot = locals.length;
		var loc:LocalVar = {
			name: name,
			slot: slot,
			depth: currentScopeDepth,
			type: type,
			isFinal: isFinal
		};
		locals.push(loc);
		if (slot + 1 > maxSlots) {
			maxSlots = slot + 1;
		}
		if (debugMode) {
			activeLocals.push({name: name, slot: slot, startIp: instructions.length});
		}
		return loc;
	}

	function resolveLocal(name:String):Null<LocalVar> {
		var i = locals.length - 1;
		while (i >= 0) {
			if (locals[i].name == name)
				return locals[i];
			i--;
		}
		return null;
	}

	function closeLocal(name:String, slot:Int) {
		var i = activeLocals.length - 1;
		while (i >= 0) {
			var active = activeLocals[i];
			if (active.name == name && active.slot == slot) {
				debugSymbols.push({
					name: name,
					slot: slot,
					startIp: active.startIp,
					endIp: instructions.length
				});
				activeLocals.splice(i, 1);
				return;
			}
			i--;
		}
	}

	function closeAllActiveLocals() {
		while (activeLocals.length > 0) {
			var active = activeLocals.pop();
			debugSymbols.push({
				name: active.name,
				slot: active.slot,
				startIp: active.startIp,
				endIp: instructions.length
			});
		}
	}

	function popScope() {
		while (locals.length > 0 && locals[locals.length - 1].depth == currentScopeDepth) {
			var loc = locals.pop();
			if (debugMode) {
				closeLocal(loc.name, loc.slot);
			}
		}
		currentScopeDepth--;
	}

	function iterExpr(e:Expr, cb:Expr->Void) {
		if (e == null)
			return;
		switch (e.def) {
			case EValue(_), EIdent(_), EBreak, EContinue, EPackage(_), EImport(_, _), EUsing(_), EEnum(_, _, _), ETypedef(_, _, _), EEReg(_, _):
				// No sub-expressions
			case EVar(_, _, expr, _, _), EUnop(_, expr), EField(expr, _), ESafeField(expr, _), EReturn(expr), EThrow(expr), ECast(expr, _), EMeta(_, expr):
				if (expr != null)
					cb(expr);
			case EAssign(e1, e2), EBinop(_, e1, e2), EWhile(e1, e2), EDoWhile(e1, e2), EFor(_, e1, e2):
				cb(e1);
				cb(e2);
			case ECall(e1, args):
				cb(e1);
				for (a in args)
					cb(a);
			case EArrayDecl(values):
				for (v in values)
					cb(v);
			case EObjectDecl(fields):
				for (f in fields)
					cb(f.expr);
			case EMapDecl(values):
				for (kv in values) {
					cb(kv.key);
					cb(kv.value);
				}
			case EBlock(exprs):
				for (ex in exprs)
					cb(ex);
			case EFunction(_, args, _, body):
				cb(body);
			case EIf(cond, e1, e2):
				cb(cond);
				cb(e1);
				if (e2 != null)
					cb(e2);
			case ESwitch(expr, cases, defExpr):
				cb(expr);
				for (c in cases) {
					for (v in c.values)
						cb(v);
					if (c.guard != null)
						cb(c.guard);
					cb(c.expr);
				}
				if (defExpr != null)
					cb(defExpr);
			case ETry(tryExpr, catches):
				cb(tryExpr);
				for (c in catches) {
					cb(c.pattern);
					if (c.guard != null)
						cb(c.guard);
					cb(c.body);
				}
			case ENew(_, args):
				for (a in args)
					cb(a);
			case EClass(_, fields, methods, _, _, _, _):
				for (f in fields)
					if (f.expr != null)
						cb(f.expr);
				for (m in methods)
					cb(m.body);
			case EInterface(_, _, methods, _, _, _):
				for (m in methods)
					if (m.body != null)
						cb(m.body);
			case EAbstract(_, _, fields, methods, _, _):
				for (f in fields)
					if (f.expr != null)
						cb(f.expr);
				for (m in methods)
					cb(m.body);
		}
	}

	function collectIdents(e:Expr, idents:Map<String, Bool>) {
		if (e == null)
			return;
		switch (e.def) {
			case EIdent(name):
				idents.set(name, true);
			default:
				iterExpr(e, child -> collectIdents(child, idents));
		}
	}

	function findCapturedVars(e:Expr, declared:Map<String, Bool>, captured:Map<String, Bool>) {
		if (e == null)
			return;
		switch (e.def) {
			case EVar(name, _, expr, _, _):
				declared.set(name, true);
				if (expr != null)
					findCapturedVars(expr, declared, captured);
			case EFor(v, itExpr, body):
				declared.set(v, true);
				findCapturedVars(itExpr, declared, captured);
				findCapturedVars(body, declared, captured);
			case ETry(tryExpr, catches):
				findCapturedVars(tryExpr, declared, captured);
				for (c in catches) {
					var catchDeclared = copyMap(declared);
					declarePatternVars(c.pattern, catchDeclared);
					if (c.guard != null)
						findCapturedVars(c.guard, catchDeclared, captured);
					findCapturedVars(c.body, catchDeclared, captured);
				}
			case EFunction(name, args, _, body):
				var funcDeclared = new Map<String, Bool>();
				for (arg in args)
					funcDeclared.set(arg.name, true);
				if (name != null)
					funcDeclared.set(name, true);

				var idents = new Map<String, Bool>();
				collectIdents(body, idents);
				for (id in idents.keys()) {
					if (!funcDeclared.exists(id) && declared.exists(id)) {
						captured.set(id, true);
					}
				}
				findCapturedVars(body, funcDeclared, captured);
			default:
				iterExpr(e, child -> findCapturedVars(child, declared, captured));
		}
	}

	function copyMap(m:Map<String, Bool>):Map<String, Bool> {
		var copy = new Map<String, Bool>();
		for (k in m.keys())
			copy.set(k, m.get(k));
		return copy;
	}

	function declarePatternVars(pat:Expr, declared:Map<String, Bool>) {
		if (pat == null)
			return;
		switch (pat.def) {
			case EIdent(name):
				if (name != "null" && name != "true" && name != "false") {
					declared.set(name, true);
				}
			default:
				iterExpr(pat, child -> declarePatternVars(child, declared));
		}
	}

	inline function emit(op:Opcode, pos:Pos) {
		instructions.push(op);
		positions.push(pos);
	}

	inline function emitInt(val:Int, pos:Pos) {
		instructions.push(val);
		positions.push(pos);
	}

	function addConst(v:Dynamic):Int {
		if (v == null || Std.isOfType(v, String) || Std.isOfType(v, Int) || Std.isOfType(v, Float) || Std.isOfType(v, Bool)) {
			for (i in 0...constants.length) {
				var c = constants[i];
				if (c == v) {
					if (Std.isOfType(c, String) && !Std.isOfType(v, String))
						continue;
					if (Std.isOfType(c, Bool) && !Std.isOfType(v, Bool))
						continue;
					if (Std.isOfType(c, Int) && !Std.isOfType(v, Int))
						continue;
					if (Std.isOfType(c, Float) && !Std.isOfType(v, Float))
						continue;
					return i;
				}
			}
		}
		constants.push(v);
		return constants.length - 1;
	}

	function compileExpr(e:Expr) {
		if (e == null) {
			emit(OP_LOAD_CONST, {line: 1, col: 1});
			emitInt(addConst(null), {line: 1, col: 1});
			return;
		}

		switch (e.def) {
			case EValue(v):
				emit(OP_LOAD_CONST, e.pos);
				emitInt(addConst(v), e.pos);

			case EEReg(pattern, flags):
				emit(OP_EREG, e.pos);
				emitInt(addConst(pattern), e.pos);
				emitInt(addConst(flags), e.pos);

			case EIdent(name):
				var loc = !isTopLevel ? resolveLocal(name) : null;
				if (loc != null && !capturedVars.exists(name)) {
					emit(OP_GET_LOCAL, e.pos);
					emitInt(loc.slot, e.pos);
				} else {
					emit(OP_GET_VAR, e.pos);
					emitInt(addConst(name), e.pos);
				}

			case EVar(name, type, expr, isFinal, meta):
				var processedExpr = ResourceCompiler.processResource(meta, type, expr, e.pos, this.resources);
				if (processedExpr != null) {
					compileExpr(processedExpr);
				} else {
					emit(OP_LOAD_CONST, e.pos);
					emitInt(addConst(null), e.pos);
				}
				var isSlot = !isTopLevel && !capturedVars.exists(name);
				if (isSlot) {
					if (type != null) {
						emit(OP_CHECK_TYPE, e.pos);
						emitInt(addConst(type), e.pos);
					}
					var loc = declareLocal(name, type, isFinal);
					emit(OP_SET_LOCAL, e.pos);
					emitInt(loc.slot, e.pos);
				} else {
					var nameIdx = addConst(name);
					var typeIdx = type != null ? addConst(type) : -1;
					emit(OP_DECLARE_VAR, e.pos);
					emitInt(nameIdx, e.pos);
					emitInt(typeIdx, e.pos);
					emitInt(isFinal ? 1 : 0, e.pos);
				}

			case EAssign(target, expr):
				switch (target.def) {
					case EIdent(name):
						var loc = !isTopLevel ? resolveLocal(name) : null;
						if (loc != null) {
							if (loc.isFinal == true) {
								throw new CompileException('Cannot reassign final variable $name', target.pos.line, target.pos.col, target.pos.file);
							}
							if (!capturedVars.exists(name)) {
								compileExpr(expr);
								if (loc.type != null) {
									emit(OP_CHECK_TYPE, e.pos);
									emitInt(addConst(loc.type), e.pos);
								}
								emit(OP_SET_LOCAL, e.pos);
								emitInt(loc.slot, e.pos);
							} else {
								compileExpr(expr);
								emit(OP_SET_VAR, e.pos);
								emitInt(addConst(name), e.pos);
							}
						} else {
							compileExpr(expr);
							emit(OP_SET_VAR, e.pos);
							emitInt(addConst(name), e.pos);
						}
					case EField(obj, field):
						compileExpr(obj);
						compileExpr(expr);
						emit(OP_SET_FIELD, e.pos);
						emitInt(addConst(field), e.pos);
					case ESafeField(obj, field):
						compileExpr(obj);
						compileExpr(expr);
						emit(OP_SAFE_SET_FIELD, e.pos);
						emitInt(addConst(field), e.pos);
					case EBinop("[]", obj, indexExpr):
						compileExpr(obj);
						compileExpr(indexExpr);
						compileExpr(expr);
						emit(OP_ARRAY_ACCESS_SET, e.pos);
					default:
						throw "Invalid assignment target";
				}

			case EBinop(op, e1, e2):
				if (op == "&&") {
					compileExpr(e1);
					emit(OP_JUMP_IF_FALSE_PEEK, e.pos);
					var jumpIdx = instructions.length;
					emitInt(0, e.pos); // placeholder
					emit(OP_POP, e.pos);
					compileExpr(e2);
					instructions[jumpIdx] = instructions.length;
				} else if (op == "||") {
					compileExpr(e1);
					emit(OP_JUMP_IF_TRUE_PEEK, e.pos);
					var jumpIdx = instructions.length;
					emitInt(0, e.pos); // placeholder
					emit(OP_POP, e.pos);
					compileExpr(e2);
					instructions[jumpIdx] = instructions.length;
				} else if (op == "??") {
					compileExpr(e1);
					emit(OP_JUMP_IF_NOT_NULL_PEEK, e.pos);
					var jumpIdx = instructions.length;
					emitInt(0, e.pos); // placeholder
					emit(OP_POP, e.pos);
					compileExpr(e2);
					instructions[jumpIdx] = instructions.length;
				} else if (op == "?") {
					compileExpr(e1);
					emit(OP_JUMP_IF_FALSE, e.pos);
					var elseJumpIdx = instructions.length;
					emitInt(0, e.pos);

					switch (e2.def) {
						case EBinop(":", left, right):
							compileExpr(left);
							emit(OP_JUMP, e.pos);
							var endJumpIdx = instructions.length;
							emitInt(0, e.pos);

							instructions[elseJumpIdx] = instructions.length;
							compileExpr(right);
							instructions[endJumpIdx] = instructions.length;
						default:
							throw "Invalid ternary operator format";
					}
				} else if (op == "[]") {
					compileExpr(e1);
					compileExpr(e2);
					emit(OP_ARRAY_ACCESS_GET, e.pos);
				} else if (op == "...") {
					compileExpr(e1);
					compileExpr(e2);
					emit(OP_RANGE, e.pos);
				} else {
					compileExpr(e1);
					compileExpr(e2);
					var opc:Opcode = switch (op) {
						case "+": OP_ADD;
						case "-": OP_SUB;
						case "*": OP_MUL;
						case "/": OP_DIV;
						case "%": OP_MOD;
						case "==": OP_EQ;
						case "!=": OP_NEQ;
						case "<": OP_LT;
						case "<=": OP_LTE;
						case ">": OP_GT;
						case ">=": OP_GTE;
						case "&": OP_BIT_AND;
						case "|": OP_BIT_OR;
						case "^": OP_BIT_XOR;
						case "<<": OP_SHL;
						case ">>": OP_SHR;
						case ">>>": OP_USHR;
						default: throw 'Unknown operator "$op"';
					};
					emit(opc, e.pos);
				}

			case EUnop(op, expr):
				if (op == "++" || op == "--" || op == "post++" || op == "post--") {
					switch (expr.def) {
						case EIdent(name):
							var loc = !isTopLevel ? resolveLocal(name) : null;
							if (loc != null && loc.isFinal == true) {
								throw new CompileException('Cannot reassign final variable $name', expr.pos.line, expr.pos.col, expr.pos.file);
							}
						default:
					}
					emit(OP_UNOP_MUTATE, e.pos);
					emitInt(addConst(op), e.pos);
					emitInt(addConst(expr), e.pos);
				} else {
					compileExpr(expr);
					emit(OP_UNOP, e.pos);
					emitInt(addConst(op), e.pos);
				}

			case EField(objExpr, field):
				compileExpr(objExpr);
				emit(OP_GET_FIELD, e.pos);
				emitInt(addConst(field), e.pos);

			case ESafeField(objExpr, field):
				compileExpr(objExpr);
				emit(OP_SAFE_GET_FIELD, e.pos);
				emitInt(addConst(field), e.pos);

			case ECall(callExpr, args):
				var isAwait = false;
				var isOnDispose = false;
				switch (callExpr.def) {
					case EField(obj, field):
						if (obj != null) {
							switch (obj.def) {
								case EIdent("HaxiomHost"):
									if (field == "await") isAwait = true;
									else if (field == "onDispose") isOnDispose = true;
								default:
							}
						}
					default:
				}

				if (isAwait) {
					if (args.length != 1) {
						throw "HaxiomHost.await expects exactly 1 argument";
					}
					compileExpr(args[0]);
					emit(OP_AWAIT, e.pos);
				} else if (isOnDispose) {
					if (args.length != 1) {
						throw "HaxiomHost.onDispose expects exactly 1 argument";
					}
					compileExpr(args[0]);
					emit(OP_ON_DISPOSE, e.pos);
				} else {
					switch (callExpr.def) {
						case EField(obj, field):
							for (arg in args) {
								compileExpr(arg);
							}
							compileExpr(obj);
							emit(OP_CALL_METHOD, e.pos);
							emitInt(addConst(field), e.pos);
							emitInt(args.length, e.pos);
						default:
							for (arg in args) {
								compileExpr(arg);
							}
							compileExpr(callExpr);
							emit(OP_CALL, e.pos);
							emitInt(args.length, e.pos);
					}
				}

			case EArrayDecl(values):
				for (val in values) {
					compileExpr(val);
				}
				emit(OP_NEW_ARRAY, e.pos);
				emitInt(values.length, e.pos);

			case EObjectDecl(fields):
				for (f in fields) {
					compileExpr(f.expr);
				}
				emit(OP_NEW_OBJECT, e.pos);
				emitInt(fields.length, e.pos);
				for (i in 0...fields.length) {
					var f = fields[fields.length - 1 - i];
					emitInt(addConst(f.name), e.pos);
				}

			case EMapDecl(values):
				for (kv in values) {
					compileExpr(kv.key);
					compileExpr(kv.value);
				}
				emit(OP_NEW_MAP, e.pos);
				emitInt(values.length, e.pos);

			case EBlock(exprs):
				var hasScope = !isTopLevel;
				if (hasScope) {
					emit(OP_PUSH_SCOPE, e.pos);
					currentScopeDepth++;
				}
				if (exprs.length == 0) {
					emit(OP_LOAD_CONST, e.pos);
					emitInt(addConst(null), e.pos);
				} else {
					for (i in 0...exprs.length) {
						compileExpr(exprs[i]);
						if (i < exprs.length - 1) {
							emit(OP_POP, e.pos);
						}
					}
				}
				if (hasScope) {
					emit(OP_POP_SCOPE, e.pos);
					popScope();
				}

			case EFunction(name, args, retType, body):
				var bodyChunk = BytecodeCompiler.compile(body, args, false, false, debugMode, name);
				// Clean the body Chunk's positions so it knows its location
				var proto = {
					name: name,
					args: args,
					retType: retType,
					bodyChunk: bodyChunk
				};
				emit(OP_MAKE_FUNCTION, e.pos);
				emitInt(addConst(proto), e.pos);

			case EIf(cond, e1, e2):
				compileExpr(cond);
				emit(OP_JUMP_IF_FALSE, e.pos);
				var elseJumpIdx = instructions.length;
				emitInt(0, e.pos);

				compileExpr(e1);
				emit(OP_JUMP, e.pos);
				var endJumpIdx = instructions.length;
				emitInt(0, e.pos);

				instructions[elseJumpIdx] = instructions.length;
				if (e2 != null) {
					compileExpr(e2);
				} else {
					emit(OP_LOAD_CONST, e.pos);
					emitInt(addConst(null), e.pos);
				}
				instructions[endJumpIdx] = instructions.length;

			case EWhile(cond, body):
				var startLabel = instructions.length;
				compileExpr(cond);
				emit(OP_JUMP_IF_FALSE, e.pos);
				var endJumpIdx = instructions.length;
				emitInt(0, e.pos);

				loopStack.push({startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth});
				var loopIdx = loopStack.length - 1;

				compileExpr(body);
				emit(OP_POP, e.pos); // clean body result
				emit(OP_JUMP, e.pos);
				emitInt(startLabel, e.pos);

				instructions[endJumpIdx] = instructions.length;
				loopStack[loopIdx].endLabel = instructions.length;

				// break jumps must go here
				// Patch break jumps that were compiled with loopEnd placeholder
				for (i in startLabel...instructions.length) {
					if (instructions[i] == -999) { // -999 is placeholder for loop end
						instructions[i] = instructions.length;
					}
					if (instructions[i] == -888) { // -888 is placeholder for loop start
						instructions[i] = startLabel;
					}
				}

				loopStack.pop();
				emit(OP_LOAD_CONST, e.pos);
				emitInt(addConst(null), e.pos);

			case EDoWhile(cond, body):
				var startLabel = instructions.length;

				loopStack.push({startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth});
				var loopIdx = loopStack.length - 1;

				compileExpr(body);
				emit(OP_POP, e.pos);

				var condLabel = instructions.length;
				compileExpr(cond);
				emit(OP_JUMP_IF_TRUE_PEEK, e.pos); // wait, jumps if true (meaning it loops back to startLabel)
				emitInt(startLabel, e.pos);
				emit(OP_POP, e.pos); // pop cond result

				loopStack[loopIdx].endLabel = instructions.length;

				// Patch breaks and continues
				for (i in startLabel...instructions.length) {
					if (instructions[i] == -999) {
						instructions[i] = instructions.length;
					}
					if (instructions[i] == -888) {
						instructions[i] = condLabel;
					}
				}

				loopStack.pop();
				emit(OP_LOAD_CONST, e.pos);
				emitInt(addConst(null), e.pos);

			case EFor(v, itExpr, body):
				compileExpr(itExpr);
				emit(OP_GET_ITERATOR, e.pos);

				var startLabel = instructions.length;
				emit(OP_ITERATOR_HAS_NEXT, e.pos);
				emit(OP_JUMP_IF_FALSE, e.pos);
				var endJumpIdx = instructions.length;
				emitInt(0, e.pos);

				emit(OP_PUSH_SCOPE, e.pos);
				currentScopeDepth++;

				emit(OP_ITERATOR_NEXT, e.pos);
				var isSlot = !isTopLevel && !capturedVars.exists(v);
				if (isSlot) {
					var loc = declareLocal(v, null);
					emit(OP_SET_LOCAL, e.pos);
					emitInt(loc.slot, e.pos);
					emit(OP_POP, e.pos);
				} else {
					emit(OP_DECLARE_VAR, e.pos);
					emitInt(addConst(v), e.pos);
					emitInt(-1, e.pos); // no type
					emitInt(0, e.pos); // not final
				}

				loopStack.push({startLabel: startLabel, endLabel: -1, scopeDepth: currentScopeDepth});
				var loopIdx = loopStack.length - 1;

				compileExpr(body);
				emit(OP_POP, e.pos);

				emit(OP_POP_SCOPE, e.pos);
				popScope();

				emit(OP_JUMP, e.pos);
				emitInt(startLabel, e.pos);

				instructions[endJumpIdx] = instructions.length;
				loopStack[loopIdx].endLabel = instructions.length;

				// Patch break/continues
				for (i in startLabel...instructions.length) {
					if (instructions[i] == -999) {
						instructions[i] = instructions.length;
					}
					if (instructions[i] == -888) {
						instructions[i] = startLabel;
					}
				}

				loopStack.pop();
				emit(OP_POP, e.pos); // pop the iterator from stack
				emit(OP_LOAD_CONST, e.pos);
				emitInt(addConst(null), e.pos);

			case EBreak:
				if (loopStack.length == 0)
					throw "Break outside loop";
				var ctx = loopStack[loopStack.length - 1];
				var scopeDiff = currentScopeDepth - ctx.scopeDepth;
				for (i in 0...scopeDiff) {
					emit(OP_POP_SCOPE, e.pos);
				}
				emit(OP_JUMP, e.pos);
				emitInt(-999, e.pos); // placeholder for loop end

			case EContinue:
				if (loopStack.length == 0)
					throw "Continue outside loop";
				var ctx = loopStack[loopStack.length - 1];
				var scopeDiff = currentScopeDepth - ctx.scopeDepth;
				for (i in 0...scopeDiff) {
					emit(OP_POP_SCOPE, e.pos);
				}
				emit(OP_JUMP, e.pos);
				emitInt(-888, e.pos); // placeholder for loop start / check

			case EReturn(exprVal):
				var isTailCall = false;
				var callArgs:Array<Expr> = null;
				if (exprVal != null && this.functionName != null) {
					switch (exprVal.def) {
						case ECall(callExpr, args):
							switch (callExpr.def) {
								case EIdent(name):
									if (name == this.functionName) {
										isTailCall = true;
										callArgs = args;
									}
								case EField(obj, field):
									if (field == this.functionName) {
										switch (obj.def) {
											case EIdent("this"):
												isTailCall = true;
												callArgs = args;
											default:
										}
									}
								default:
							}
						default:
					}
				}

				if (isTailCall) {
					var numArgs = this.args != null ? this.args.length : 0;
					// Evaluate each call argument and push onto the stack using compileExpr
					for (arg in callArgs) {
						compileExpr(arg);
					}

					// Pop values in reverse order and store in parameter registers
					var m = callArgs.length;
					var i = m - 1;
					while (i >= 0) {
						if (i < numArgs) {
							emit(OP_SET_LOCAL, e.pos);
							emitInt(i, e.pos);
							emit(OP_POP, e.pos);
						} else {
							// Extra argument passed to recursive call - discard it
							emit(OP_POP, e.pos);
						}
						i--;
					}

					// If the recursive call passed fewer arguments than the function expects,
					// we must set the remaining parameter slots to null to prevent retaining old values.
					for (j in callArgs.length...numArgs) {
						emit(OP_LOAD_CONST, e.pos);
						emitInt(addConst(null), e.pos);
						emit(OP_SET_LOCAL, e.pos);
						emitInt(j, e.pos);
						emit(OP_POP, e.pos);
					}

					// Clean up lexical scopes by emitting OP_POP_SCOPE exactly currentScopeDepth times
					for (k in 0...currentScopeDepth) {
						emit(OP_POP_SCOPE, e.pos);
					}

					// Emit OP_JUMP to absolute position 0
					emit(OP_JUMP, e.pos);
					emitInt(0, e.pos);
				} else {
					if (exprVal != null) {
						compileExpr(exprVal);
					} else {
						emit(OP_LOAD_CONST, e.pos);
						emitInt(addConst(null), e.pos);
					}
					emit(OP_RETURN, e.pos);
				}

			case EThrow(exprVal):
				compileExpr(exprVal);
				emit(OP_THROW, e.pos);

			case ETry(tryExpr, catches):
				emit(OP_PUSH_TRY, e.pos);
				var catchJumpIdx = instructions.length;
				emitInt(0, e.pos);

				compileExpr(tryExpr);
				emit(OP_POP_TRY, e.pos);
				emit(OP_JUMP, e.pos);
				var endTryJumpIdx = instructions.length;
				emitInt(0, e.pos);

				instructions[catchJumpIdx] = instructions.length;

				// Catches block: top of stack has the exception
				for (i in 0...catches.length) {
					var c = catches[i];
					var clauseIdx = addConst(c);
					emit(OP_MATCH_CATCH, e.pos);
					emitInt(clauseIdx, e.pos);

					emit(OP_JUMP_IF_FALSE, e.pos);
					var nextCatchJumpIdx = instructions.length;
					emitInt(0, e.pos);

					// Matches: caseScope is on stack
					emit(OP_PUSH_CASE_SCOPE, e.pos);
					currentScopeDepth++;

					compileExpr(c.body);

					emit(OP_POP_SCOPE, e.pos);
					popScope();

					emit(OP_JUMP, e.pos);
					var exitTryJumpIdx = instructions.length;
					emitInt(0, e.pos);

					instructions[nextCatchJumpIdx] = instructions.length;
					// If we exit this catch, continue to next or throw
					if (i == catches.length - 1) {
						// Rethrow exception
						emit(OP_THROW, e.pos);
					}

					// Patch exit Try jumps
					instructions[exitTryJumpIdx] = endTryJumpIdx; // we patch it later to end of try
				}

				// Patch end Try jumps
				var finalEndOffset = instructions.length;
				instructions[endTryJumpIdx] = finalEndOffset;
				for (i in catchJumpIdx...instructions.length) {
					if (instructions[i] == endTryJumpIdx) {
						instructions[i] = finalEndOffset;
					}
				}

			case ESwitch(exprVal, cases, defExpr):
				compileExpr(exprVal); // leaves match val on stack

				var endSwitchJumpIndices = [];

				for (c in cases) {
					var caseBodyLabel = -1;
					var valueJumpPlaceholderIndices = [];

					for (v in c.values) {
						var patternIdx = addConst(v);
						var guardIdx = c.guard != null ? addConst(c.guard) : -1;
						emit(OP_MATCH_CASE, e.pos);
						emitInt(patternIdx, e.pos);
						emitInt(guardIdx, e.pos);

						emit(OP_JUMP_IF_TRUE_PEEK, e.pos);
						valueJumpPlaceholderIndices.push(instructions.length);
						emitInt(0, e.pos); // placeholder to jump to body

						emit(OP_POP, e.pos); // pop false if match failed
					}

					emit(OP_JUMP, e.pos);
					var skipBodyJumpIdx = instructions.length;
					emitInt(0, e.pos);

					// Case body
					var bodyLabel = instructions.length;
					for (idx in valueJumpPlaceholderIndices) {
						instructions[idx] = bodyLabel;
					}

					emit(OP_POP, e.pos); // pop true from OP_JUMP_IF_TRUE_PEEK
					emit(OP_PUSH_CASE_SCOPE, e.pos);
					currentScopeDepth++;

					compileExpr(c.expr);

					emit(OP_POP_SCOPE, e.pos);
					popScope();

					emit(OP_JUMP, e.pos);
					endSwitchJumpIndices.push(instructions.length);
					emitInt(0, e.pos);

					instructions[skipBodyJumpIdx] = instructions.length;
				}

				// If we get here, no case matched
				emit(OP_POP, e.pos); // pop match val

				if (defExpr != null) {
					compileExpr(defExpr);
				} else {
					emit(OP_LOAD_CONST, e.pos);
					emitInt(addConst(null), e.pos);
				}

				var endLabel = instructions.length;
				for (idx in endSwitchJumpIndices) {
					instructions[idx] = endLabel;
				}

			case ENew(type, args):
				for (arg in args) {
					compileExpr(arg);
				}
				emit(OP_NEW, e.pos);
				emitInt(addConst(type), e.pos);
				emitInt(args.length, e.pos);

			case ECast(exprVal, type):
				compileExpr(exprVal);
				emit(OP_CAST, e.pos);
				emitInt(type != null ? addConst(type) : -1, e.pos);

			case EClass(name, fields, methods, parent, interfaces, params, meta, isExtern):
				if (isExtern == true)
					return;
				for (f in fields) {
					if (f.meta != null) {
						f.expr = ResourceCompiler.processResource(f.meta, f.type, f.expr, e.pos, this.resources);
					}
				}
				for (m in methods) {
					if (m.body != null) {
						var isMethodAsync = false;
						if (m.meta != null) {
							for (meta in m.meta) {
								if (meta.name == ":haxiom.async") {
									isMethodAsync = true;
									break;
								}
							}
						}
						var mDyn:Dynamic = m;
						mDyn.bytecodeChunk = BytecodeCompiler.compile(m.body, m.args, false, isMethodAsync, debugMode, m.name);
						if (!debugMode) {
							m.body = null;
						}
					}
				}
				emit(OP_DECLARE_CLASS, e.pos);
				emitInt(addConst(e), e.pos);

			case EInterface(name, fields, methods, parents, params, meta):
				emit(OP_DECLARE_INTERFACE, e.pos);
				emitInt(addConst(e), e.pos);

			case EEnum(name, constructors, _):
				emit(OP_DECLARE_ENUM, e.pos);
				emitInt(addConst(e), e.pos);

			case EAbstract(name, underlyingType, fields, methods, params, meta):
				for (f in fields) {
					if (f.meta != null) {
						f.expr = ResourceCompiler.processResource(f.meta, f.type, f.expr, e.pos, this.resources);
					}
				}
				for (m in methods) {
					if (m.body != null) {
						var isMethodAsync = false;
						if (m.meta != null) {
							for (meta in m.meta) {
								if (meta.name == ":haxiom.async") {
									isMethodAsync = true;
									break;
								}
							}
						}
						var mDyn:Dynamic = m;
						mDyn.bytecodeChunk = BytecodeCompiler.compile(m.body, m.args, false, isMethodAsync, debugMode, m.name);
						if (!debugMode) {
							m.body = null;
						}
					}
				}
				emit(OP_DECLARE_ABSTRACT, e.pos);
				emitInt(addConst(e), e.pos);

			case ETypedef(name, type, params):
				emit(OP_DECLARE_TYPEDEF, e.pos);
				emitInt(addConst(e), e.pos);

			case EImport(path, alias):
				emit(OP_IMPORT, e.pos);
				emitInt(addConst(e), e.pos);

			case EUsing(path):
				emit(OP_USING, e.pos);
				emitInt(addConst(e), e.pos);

			case EPackage(path):
				emit(OP_PACKAGE, e.pos);
				emitInt(addConst(e), e.pos);

			case EMeta(meta, exprVal):
				var isTargetAsync = false;
				for (m in meta) {
					if (m.name == ":haxiom.async") {
						isTargetAsync = true;
						break;
					}
				}

				if (isTargetAsync) {
					switch (exprVal.def) {
						case EFunction(name, args, retType, body):
							var bodyChunk = BytecodeCompiler.compile(body, args, false, true, debugMode, name);
							var proto = {
								name: name,
								args: args,
								retType: retType,
								bodyChunk: bodyChunk
							};
							emit(OP_MAKE_FUNCTION, exprVal.pos);
							emitInt(addConst(proto), exprVal.pos);
						default:
							compileExpr(exprVal);
					}
				} else {
					compileExpr(exprVal);
				}

			default:
				throw 'Unsupported compile AST node: ${Type.enumConstructor(e.def)}';
		}
	}

	static var dummyPos:Pos = {line: 1, col: 1, file: "script"};

	static function stripPositions(expr:Expr):Void {
		if (expr == null)
			return;
		expr.pos = dummyPos;
		switch (expr.def) {
			case EClass(_, fields, methods, _, _, _, meta):
				for (f in fields) {
					if (f.expr != null)
						stripPositions(f.expr);
					if (f.meta != null) {
						for (m in f.meta) {
							if (m.params != null) {
								for (p in m.params)
									stripPositions(p);
							}
						}
					}
				}
				for (m in methods) {
					if (m.body != null)
						stripPositions(m.body);
					var mDyn:Dynamic = m;
					if (mDyn.bytecodeChunk != null) {
						stripPositionsFromChunk(mDyn.bytecodeChunk);
					}
					if (m.meta != null) {
						for (meta in m.meta) {
							if (meta.params != null) {
								for (p in meta.params)
									stripPositions(p);
							}
						}
					}
				}
				if (meta != null) {
					for (m in meta) {
						if (m.params != null) {
							for (p in m.params)
								stripPositions(p);
						}
					}
				}
			case EFunction(_, _, _, body):
				stripPositions(body);
			case EBlock(exprs):
				for (e in exprs)
					stripPositions(e);
			case EVar(_, _, expr, _, meta):
				if (expr != null)
					stripPositions(expr);
				if (meta != null) {
					for (m in meta) {
						if (m.params != null) {
							for (p in m.params)
								stripPositions(p);
						}
					}
				}
			case EAssign(target, e):
				stripPositions(target);
				stripPositions(e);
			case EBinop(_, e1, e2):
				stripPositions(e1);
				stripPositions(e2);
			case EUnop(_, e):
				stripPositions(e);
			case EField(e, _):
				stripPositions(e);
			case ESafeField(e, _):
				stripPositions(e);
			case ECall(e, args):
				stripPositions(e);
				for (a in args)
					stripPositions(a);
			case ENew(_, args):
				for (a in args)
					stripPositions(a);
			case EArrayDecl(values):
				for (v in values)
					stripPositions(v);
			case EObjectDecl(fields):
				for (f in fields)
					stripPositions(f.expr);
			case EMapDecl(values):
				for (v in values) {
					stripPositions(v.key);
					stripPositions(v.value);
				}
			case EIf(cond, e1, e2):
				stripPositions(cond);
				stripPositions(e1);
				if (e2 != null)
					stripPositions(e2);
			case EWhile(cond, e):
				stripPositions(cond);
				stripPositions(e);
			case EDoWhile(cond, e):
				stripPositions(cond);
				stripPositions(e);
			case EFor(_, it, e):
				stripPositions(it);
				stripPositions(e);
			case ESwitch(e, cases, defExpr):
				stripPositions(e);
				for (c in cases) {
					for (v in c.values)
						stripPositions(v);
					if (c.guard != null)
						stripPositions(c.guard);
					stripPositions(c.expr);
				}
				if (defExpr != null)
					stripPositions(defExpr);
			case EReturn(e):
				if (e != null)
					stripPositions(e);
			case EThrow(e):
				stripPositions(e);
			case ETry(tryExpr, catches):
				stripPositions(tryExpr);
				for (c in catches) {
					stripPositions(c.pattern);
					if (c.guard != null)
						stripPositions(c.guard);
					stripPositions(c.body);
				}
			case ECast(e, _):
				stripPositions(e);
			case EMeta(meta, e):
				for (m in meta) {
					if (m.params != null) {
						for (p in m.params)
							stripPositions(p);
					}
				}
				stripPositions(e);
			case EInterface(_, fields, methods, _, _, meta):
				for (f in fields) {
					if (f.meta != null) {
						for (m in f.meta) {
							if (m.params != null) {
								for (p in m.params)
									stripPositions(p);
							}
						}
					}
				}
				for (m in methods) {
					if (m.body != null)
						stripPositions(m.body);
					if (m.meta != null) {
						for (meta in m.meta) {
							if (meta.params != null) {
								for (p in meta.params)
									stripPositions(p);
							}
						}
					}
				}
				if (meta != null) {
					for (m in meta) {
						if (m.params != null) {
							for (p in m.params)
								stripPositions(p);
						}
					}
				}
			case EAbstract(_, _, fields, methods, _, meta):
				for (f in fields) {
					if (f.expr != null)
						stripPositions(f.expr);
					if (f.meta != null) {
						for (m in f.meta) {
							if (m.params != null) {
								for (p in m.params)
									stripPositions(p);
							}
						}
					}
				}
				for (m in methods) {
					if (m.body != null)
						stripPositions(m.body);
					var mDyn:Dynamic = m;
					if (mDyn.bytecodeChunk != null) {
						stripPositionsFromChunk(mDyn.bytecodeChunk);
					}
					if (m.meta != null) {
						for (meta in m.meta) {
							if (meta.params != null) {
								for (p in meta.params)
									stripPositions(p);
							}
						}
					}
				}
				if (meta != null) {
					for (m in meta) {
						if (m.params != null) {
							for (p in m.params)
								stripPositions(p);
						}
					}
				}
			default:
				// Leaf/structural expressions
		}
	}

	static function stripPositionsFromChunk(chunk:BytecodeChunk):Void {
		if (chunk == null || chunk.constants == null)
			return;
		for (c in chunk.constants) {
			if (c == null || Std.isOfType(c, haxe.io.Bytes))
				continue;
			if (Reflect.hasField(c, "def") && Reflect.hasField(c, "pos")) {
				stripPositions(cast c);
			} else if (Reflect.hasField(c, "bodyChunk")) {
				var proto:Dynamic = c;
				if (proto.bodyChunk != null) {
					stripPositionsFromChunk(proto.bodyChunk);
				}
			}
		}
	}

	static function optimizeChunk(chunk:BytecodeChunk):Void {
		if (chunk == null)
			return;
		optimizeBytecode(chunk.instructions, chunk.constants, chunk.positions, chunk.debugSymbols);
		if (chunk.constants != null) {
			for (c in chunk.constants) {
				if (c == null || Std.isOfType(c, haxe.io.Bytes))
					continue;
				if (Reflect.hasField(c, "bodyChunk")) {
					var proto:Dynamic = c;
					if (proto.bodyChunk != null) {
						optimizeChunk(proto.bodyChunk);
					}
				}
			}
		}
	}

	static function optimizeBytecode(instructions:Array<Int>, constants:Array<Dynamic>, positions:Array<Pos>, debugSymbols:Null<Array<DebugSymbol>>):Void {
		var ip = 0;
		var newInst:Array<Int> = [];
		var newPos:Array<Pos> = [];
		var oldToNewIP:Array<Int> = [for (i in 0...instructions.length) -1];

		while (ip < instructions.length) {
			var op = instructions[ip];
			var len = getInstructionLength(instructions, ip);

			// Record mapping for the current instruction start
			oldToNewIP[ip] = newInst.length;
			for (offset in 1...len) {
				if (ip + offset < instructions.length) {
					oldToNewIP[ip + offset] = newInst.length;
				}
			}

			// Check patterns

			// Pattern 1: Redundant NOP
			if (op == OP_NOP) {
				ip += len;
				continue;
			}

			// Pattern 2: OP_LOAD_CONST followed by OP_POP (Redundant load and discard)
			if (op == OP_LOAD_CONST && ip + len < instructions.length) {
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];
				if (nextOp == OP_POP) {
					var nextLen = getInstructionLength(instructions, nextIp);
					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = newInst.length;
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Pattern 3: OP_GET_LOCAL X followed by OP_SET_LOCAL X (Redundant get and set back to same local slot)
			if (op == OP_GET_LOCAL && ip + len < instructions.length) {
				var localSlot = instructions[ip + 1];
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];
				if (nextOp == OP_SET_LOCAL && instructions[nextIp + 1] == localSlot) {
					var nextLen = getInstructionLength(instructions, nextIp);
					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = newInst.length;
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Pattern 4: OP_SET_LOCAL X followed by OP_GET_LOCAL X -> replace with OP_DUP + OP_SET_LOCAL X
			if (op == OP_SET_LOCAL && ip + len < instructions.length) {
				var localSlot = instructions[ip + 1];
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];
				if (nextOp == OP_GET_LOCAL && instructions[nextIp + 1] == localSlot) {
					var nextLen = getInstructionLength(instructions, nextIp);
					var dupPos = (positions != null && ip < positions.length) ? positions[ip] : {line: 1, col: 1};
					newInst.push(OP_DUP);
					if (positions != null && positions.length > 0)
						newPos.push(dupPos);

					newInst.push(OP_SET_LOCAL);
					newInst.push(localSlot);
					if (positions != null && positions.length > 0) {
						newPos.push(dupPos);
						newPos.push(dupPos);
					}

					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = oldToNewIP[ip];
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Pattern 5: OP_LOAD_CONST of a boolean/null followed by OP_JUMP_IF_FALSE
			if (op == OP_LOAD_CONST && ip + len < instructions.length) {
				var constIdx = instructions[ip + 1];
				var constVal = constants[constIdx];
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];

				if (nextOp == OP_JUMP_IF_FALSE) {
					var nextLen = getInstructionLength(instructions, nextIp);
					var targetIp = instructions[nextIp + 1];
					var isTruthy = (constVal != null && constVal != false);
					var shouldJump = !isTruthy;

					if (shouldJump) {
						var jumpPos = (positions != null && ip < positions.length) ? positions[ip] : {line: 1, col: 1};
						newInst.push(OP_JUMP);
						newInst.push(targetIp);
						if (positions != null && positions.length > 0) {
							newPos.push(jumpPos);
							newPos.push(jumpPos);
						}
					} else {
						// Fall-through, no-op
					}

					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = oldToNewIP[ip];
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Pattern 6: Redundant Fall-through OP_JUMP
			if (op == OP_JUMP) {
				var targetIp = instructions[ip + 1];
				if (targetIp == ip + len) {
					for (offset in 0...len) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = newInst.length;
						}
					}
					ip += len;
					continue;
				}
			}

			// Pattern 7: Redundant Conditional JUMP to Next IP
			if (op == OP_JUMP_IF_FALSE) {
				var targetIp = instructions[ip + 1];
				if (targetIp == ip + len) {
					var popPos = (positions != null && ip < positions.length) ? positions[ip] : {line: 1, col: 1};
					newInst.push(OP_POP);
					if (positions != null && positions.length > 0) {
						newPos.push(popPos);
					}
					for (offset in 0...len) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = oldToNewIP[ip];
						}
					}
					ip += len;
					continue;
				}
			}

			// Pattern 8: OP_DUP followed by OP_POP
			if (op == OP_DUP && ip + len < instructions.length) {
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];
				if (nextOp == OP_POP) {
					var nextLen = getInstructionLength(instructions, nextIp);
					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = newInst.length;
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Pattern 9: OP_GET_LOCAL followed by OP_POP
			if (op == OP_GET_LOCAL && ip + len < instructions.length) {
				var nextIp = ip + len;
				var nextOp = instructions[nextIp];
				if (nextOp == OP_POP) {
					var nextLen = getInstructionLength(instructions, nextIp);
					for (offset in 0...(len + nextLen)) {
						if (ip + offset < instructions.length) {
							oldToNewIP[ip + offset] = newInst.length;
						}
					}
					ip += len + nextLen;
					continue;
				}
			}

			// Standard copy
			for (offset in 0...len) {
				if (ip + offset < instructions.length) {
					newInst.push(instructions[ip + offset]);
					if (positions != null && positions.length > ip + offset) {
						newPos.push(positions[ip + offset]);
					}
				}
			}
			ip += len;
		}

		// Post-pass 1: Fill any remaining unmapped indices
		var lastValidNewIP = newInst.length;
		var i = oldToNewIP.length - 1;
		while (i >= 0) {
			if (oldToNewIP[i] == -1) {
				oldToNewIP[i] = lastValidNewIP;
			} else {
				lastValidNewIP = oldToNewIP[i];
			}
			i--;
		}

		// Pass 2: Rewrite jump targets
		var newIp = 0;
		while (newIp < newInst.length) {
			var op = newInst[newIp];
			var len = getInstructionLength(newInst, newIp);

			switch (op) {
				case OP_JUMP | OP_JUMP_IF_FALSE | OP_JUMP_IF_FALSE_PEEK | OP_JUMP_IF_TRUE_PEEK | OP_JUMP_IF_NOT_NULL_PEEK:
					var oldTarget = newInst[newIp + 1];
					var newTarget = (oldTarget == instructions.length) ? newInst.length : oldToNewIP[oldTarget];
					newTarget = getJumpDest(newInst, newTarget);

					if (newTarget == newIp + len || isOnlyNops(newInst, newIp + len, newTarget)) {
						if (op == OP_JUMP) {
							newInst[newIp] = OP_NOP;
							newInst[newIp + 1] = OP_NOP;
						} else if (op == OP_JUMP_IF_FALSE) {
							newInst[newIp] = OP_POP;
							newInst[newIp + 1] = OP_NOP;
						} else {
							newInst[newIp] = OP_NOP;
							newInst[newIp + 1] = OP_NOP;
						}
					} else {
						newInst[newIp + 1] = newTarget;
					}

				case OP_PUSH_TRY:
					var oldCatch = newInst[newIp + 1];
					var newCatch = (oldCatch == instructions.length) ? newInst.length : oldToNewIP[oldCatch];
					newInst[newIp + 1] = newCatch;

				default:
			}
			newIp += len;
		}

		// Pass 3: Remap debugSymbols bounds
		if (debugSymbols != null) {
			for (sym in debugSymbols) {
				sym.startIp = sym.startIp < oldToNewIP.length ? oldToNewIP[sym.startIp] : newInst.length;
				sym.endIp = sym.endIp < oldToNewIP.length ? oldToNewIP[sym.endIp] : newInst.length;
			}
		}

		// Replace contents of original array
		#if haxe4
		instructions.resize(0);
		#else
		while (instructions.length > 0)
			instructions.pop();
		#end
		for (x in newInst)
			instructions.push(x);

		if (positions != null && positions.length > 0) {
			#if haxe4
			positions.resize(0);
			#else
			while (positions.length > 0)
				positions.pop();
			#end
			for (p in newPos)
				positions.push(p);
		}
	}

	static function isOnlyNops(newInst:Array<Int>, start:Int, end:Int):Bool {
		if (end <= start)
			return false;
		var i = start;
		while (i < end && i < newInst.length) {
			if (newInst[i] != OP_NOP)
				return false;
			i++;
		}
		return true;
	}

	static function getJumpDest(newInst:Array<Int>, target:Int):Int {
		var visited = new Map<Int, Bool>();
		var curr = target;
		while (curr < newInst.length) {
			if (newInst[curr] == OP_JUMP) {
				if (visited.exists(curr))
					break;
				visited.set(curr, true);
				curr = newInst[curr + 1];
			} else if (newInst[curr] == OP_NOP) {
				curr++;
			} else {
				break;
			}
		}
		return curr;
	}

	static function getInstructionLength(inst:Array<Int>, ip:Int):Int {
		var op = inst[ip];
		return switch (op) {
			case OP_NOP | OP_ADD | OP_SUB | OP_MUL | OP_DIV | OP_MOD | OP_EQ | OP_NEQ | OP_LT | OP_LTE | OP_GT | OP_GTE | OP_AND | OP_OR | OP_NOT |
				OP_BIT_AND | OP_BIT_OR | OP_BIT_XOR | OP_BIT_NOT | OP_SHL | OP_SHR | OP_USHR | OP_RETURN | OP_THROW | OP_GET_THIS | OP_POP | OP_PUSH_SCOPE |
				OP_POP_SCOPE | OP_GET_ITERATOR | OP_ITERATOR_HAS_NEXT | OP_ITERATOR_NEXT | OP_POP_TRY | OP_ARRAY_ACCESS_GET | OP_ARRAY_ACCESS_SET | OP_DUP |
				OP_RANGE | OP_AWAIT | OP_PUSH_CASE_SCOPE | OP_ON_DISPOSE:
				1;

			case OP_LOAD_CONST | OP_GET_LOCAL | OP_SET_LOCAL | OP_GET_VAR | OP_SET_VAR | OP_JUMP | OP_JUMP_IF_FALSE | OP_JUMP_IF_FALSE_PEEK |
				OP_JUMP_IF_TRUE_PEEK | OP_JUMP_IF_NOT_NULL_PEEK | OP_CALL | OP_GET_FIELD | OP_SET_FIELD | OP_NEW_ARRAY | OP_MAKE_FUNCTION | OP_PUSH_TRY |
				OP_MATCH_CATCH | OP_SAFE_GET_FIELD | OP_SAFE_SET_FIELD | OP_CAST | OP_DECLARE_CLASS | OP_DECLARE_INTERFACE | OP_DECLARE_ENUM |
				OP_DECLARE_ABSTRACT | OP_DECLARE_TYPEDEF | OP_IMPORT | OP_USING | OP_PACKAGE | OP_NEW_MAP | OP_CHECK_TYPE | OP_UNOP:
				2;

			case OP_CALL_METHOD | OP_MATCH_CASE | OP_NEW | OP_UNOP_MUTATE | OP_EREG:
				3;

			case OP_DECLARE_VAR:
				4;

			case OP_NEW_OBJECT:
				var fieldCount = inst[ip + 1];
				2 + fieldCount;

			default:
				throw 'Unknown opcode in optimizer: $op';
		}
	}

	static function hasAwait(expr:Expr):Bool {
		if (expr == null)
			return false;
		switch (expr.def) {
			case ECall(e, args):
				switch (e.def) {
					case EField(obj, field):
						switch (obj.def) {
							case EIdent(name):
								if (name == "HaxiomHost" && field == "await") return true;
							default:
						}
					default:
				}
				if (hasAwait(e))
					return true;
				for (arg in args) {
					if (hasAwait(arg))
						return true;
				}
			case EFunction(_, _, _, _):
				return false;
			case EVar(_, _, init, _, _):
				if (hasAwait(init))
					return true;
			case EAssign(target, e):
				if (hasAwait(target) || hasAwait(e))
					return true;
			case EBinop(_, e1, e2):
				if (hasAwait(e1) || hasAwait(e2))
					return true;
			case EUnop(_, e):
				if (hasAwait(e))
					return true;
			case EField(e, _):
				if (hasAwait(e))
					return true;
			case EArrayDecl(values):
				for (v in values) {
					if (hasAwait(v))
						return true;
				}
			case EObjectDecl(fields):
				for (f in fields) {
					if (hasAwait(f.expr))
						return true;
				}
			case EMapDecl(values):
				for (v in values) {
					if (hasAwait(v.key) || hasAwait(v.value))
						return true;
				}
			case EBlock(exprs):
				for (ex in exprs) {
					if (hasAwait(ex))
						return true;
				}
			case EIf(cond, e1, e2):
				if (hasAwait(cond) || hasAwait(e1) || hasAwait(e2))
					return true;
			case EWhile(cond, e):
				if (hasAwait(cond) || hasAwait(e))
					return true;
			case EDoWhile(cond, e):
				if (hasAwait(cond) || hasAwait(e))
					return true;
			case EFor(_, it, e):
				if (hasAwait(it) || hasAwait(e))
					return true;
			case ESwitch(e, cases, defExpr):
				if (hasAwait(e))
					return true;
				for (c in cases) {
					for (val in c.values) {
						if (hasAwait(val))
							return true;
					}
					if (hasAwait(c.guard))
						return true;
					if (hasAwait(c.expr))
						return true;
				}
				if (hasAwait(defExpr))
					return true;
			case EReturn(e):
				if (hasAwait(e))
					return true;
			case EThrow(e):
				if (hasAwait(e))
					return true;
			case ETry(tryExpr, catches):
				if (hasAwait(tryExpr))
					return true;
				for (c in catches) {
					if (hasAwait(c.pattern))
						return true;
					if (hasAwait(c.guard))
						return true;
					if (hasAwait(c.body))
						return true;
				}
			case ECast(e, _):
				if (hasAwait(e))
					return true;
			case ESafeField(e, _):
				if (hasAwait(e))
					return true;
			case ENew(_, args):
				for (arg in args) {
					if (hasAwait(arg))
						return true;
				}
			case EMeta(_, e):
				if (hasAwait(e))
					return true;
			default:
		}
		return false;
	}
}
