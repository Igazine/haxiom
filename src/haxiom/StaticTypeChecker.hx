package haxiom;

import haxiom.AST;
import haxiom.Interp;
import haxiom.CompileException;

/**
 * Performs an optional compile-time static type checking pass over the Haxiom AST.
 * 
 * Call `StaticTypeChecker.check(ast, interp)` immediately after compilation to detect
 * type mismatches such as:
 *   - Pushing wrong element types into `Array<T>`
 *   - Adding wrong element types to `List<T>`
 *   - Wrong key/value types for `Map<K,V>`
 *   - Struct field types mismatched against typedefs
 *   - Enum constructor argument type mismatches
 *   - Class constructor argument type mismatches
 */
@:allow(haxiom)
class StaticTypeChecker {
	/**
	 * Run the static type checking pass over the given AST.
	 * Throws a CompileException on the first detected type error.
	 */
	static function check(expr:Expr, interp:Interp):Void {
		var checker = new StaticTypeChecker(interp);
		checker.collectDeclarations(expr);
		checker.checkExpr(expr, new LocalEnv(null));
	}

	// -------------------------------------------------------------------------
	var interp:Interp;

	// Top-level declared classes, enums, typedefs in scope
	var classes:Map<String, ClassInfo> = new Map();
	var enums:Map<String, EnumInfo> = new Map();
	var typedefs:Map<String, TypedefInfo> = new Map();

	function new(interp:Interp) {
		this.interp = interp;
	}

	// -------------------------------------------------------------------------
	// Pass 1: collect top-level type declarations
	// -------------------------------------------------------------------------

	function collectDeclarations(expr:Expr):Void {
		if (expr == null)
			return;
		switch (expr.def) {
			case EBlock(exprs):
				for (e in exprs)
					collectDeclarations(e);

			case EClass(name, fields, methods, parent, interfaces, params, meta, isExtern):
				if (isExtern == true) {
					// Register extern class info without checking bodies
					var info = new ClassInfo(name, params != null ? params : []);
					info.isExtern = true;
					info.meta = meta;
					for (m in methods) {
						var mCopy = {
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: null,
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							isOverride: m.isOverride,
							isAbstract: m.isAbstract,
							meta: m.meta,
							isExtern: m.isExtern
						};
						info.methods.set(m.name, mCopy);
					}
					for (f in fields) {
						info.fields.set(f.name, {
							type: f.type,
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							meta: f.meta,
							isExtern: f.isExtern
						});
					}
					classes.set(name, info);
					return;
				}
				var info = new ClassInfo(name, params != null ? params : []);
				info.isAbstract = hasMeta(meta, ":abstract");
				info.meta = meta;
				if (parent != null) {
					switch (parent) {
						case TPath(path, _):
							info.parentName = path.join(".");
						default:
					}
				}
				if (interfaces != null) {
					for (itf in interfaces) {
						switch (itf) {
							case TPath(path, _):
								info.interfaces.push(path.join("."));
							default:
						}
					}
				}
				for (m in methods) {
					if (m.name == "new") {
						info.ctorArgs = m.args;
					} else {
						var finalRet = m.retType;
						if (m.body != null && hasAwait(m.body)) {
							var alreadyFuture = false;
							if (finalRet != null) {
								switch (finalRet) {
									case TPath(path, _):
										var pathStr = path.join(".");
										if (pathStr == "haxiom.guest.Future") {
											alreadyFuture = true;
										}
									default:
								}
							}
							if (!alreadyFuture && finalRet != null) {
								finalRet = TPath(["haxiom", "guest", "Future"], [finalRet]);
							} else if (finalRet == null) {
								finalRet = TPath(["haxiom", "guest", "Future"], [TPath(["Dynamic"], [])]);
							}
						}
						var mCopy = {
							name: m.name,
							args: m.args,
							retType: finalRet,
							body: m.body,
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							isOverride: m.isOverride,
							isAbstract: m.isAbstract,
							meta: m.meta
						};
						info.methods.set(m.name, mCopy);
					}
				}
				for (f in fields) {
					info.fields.set(f.name, {
						type: f.type,
						isStatic: f.isStatic,
						isPublic: f.isPublic,
						meta: f.meta
					});
				}
				classes.set(name, info);

			case EInterface(name, fields, methods, parents, params, _):
				var info = new ClassInfo(name, params != null ? params : []);
				if (parents != null) {
					for (p in parents) {
						switch (p) {
							case TPath(path, _):
								info.parentName = path.join(".");
							default:
						}
					}
				}
				for (m in methods) {
					var mCopy = {
						name: m.name,
						args: m.args,
						retType: m.retType,
						body: m.body,
						isStatic: false,
						isPublic: true // Interface methods are always public
					};
					info.methods.set(m.name, mCopy);
				}
				for (f in fields) {
					info.fields.set(f.name, {
						type: f.type,
						isStatic: false,
						isPublic: true // Interface fields are always public
					});
				}
				classes.set(name, info);

			case EEnum(name, constructors, params):
				var info = new EnumInfo(name, params != null ? params : []);
				for (c in constructors) {
					info.constructors.set(c.name, c.args != null ? c.args : []);
				}
				enums.set(name, info);

			case ETypedef(name, type, params):
				typedefs.set(name, new TypedefInfo(name, type, params != null ? params : []));

			default:
		}
	}

	// -------------------------------------------------------------------------
	// Pass 2: type inference & checking
	// -------------------------------------------------------------------------

	function checkExpr(expr:Expr, env:LocalEnv):Void {
		if (expr == null)
			return;
		switch (expr.def) {
			case EBlock(exprs):
				var childEnv = new LocalEnv(env);
				for (e in exprs)
					checkExpr(e, childEnv);

			case EVar(name, declaredType, initExpr, _, _):
				if (initExpr != null) {
					var inferredType = inferType(initExpr, env);
					if (declaredType != null) {
						checkCompatibility(inferredType, declaredType, env, initExpr.pos, name);
					}
					// Recurse into init expr to catch nested type errors
					// (e.g. enum/class ctor calls with wrong argument types)
					checkExprWithContext(initExpr, env, declaredType);
					// Bind variable with the declared type (or inferred if no annotation)
					env.set(name, declaredType != null ? declaredType : inferredType);
				} else {
					if (declaredType != null)
						env.set(name, declaredType);
				}

			case EAssign(target, rhs):
				var rhsType = inferType(rhs, env);
				var targetType = inferType(target, env);
				if (targetType != null) {
					checkCompatibility(rhsType, targetType, env, rhs.pos, null);
				}

			case ECall(e, args):
				// Check method calls like arr.push(...), list.add(...), map.set(...)
				checkCall(e, args, env, expr.pos);

			case ENew(type, args):
				checkNewExpr(type, args, env, expr.pos);

			case EIf(cond, e1, e2):
				checkExpr(cond, env);
				checkExpr(e1, env);
				if (e2 != null)
					checkExpr(e2, env);

			case EWhile(cond, body) | EDoWhile(cond, body):
				checkExpr(cond, env);
				checkExpr(body, env);

			case EFor(v, it, body):
				var childEnv = new LocalEnv(env);
				// Infer element type from iterator
				var elemType = inferIteratorElemType(it, env);
				childEnv.set(v, elemType);
				checkExpr(body, childEnv);

			case EReturn(e):
				if (e != null)
					checkExpr(e, env);

			case EThrow(e):
				checkExpr(e, env);

			case ETry(tryExpr, catches):
				checkExpr(tryExpr, env);
				for (c in catches) {
					var catchEnv = new LocalEnv(env);
					switch (c.pattern.def) {
						case EIdent(varName):
							if (c.type != null) catchEnv.set(varName, c.type);
						default:
					}
					checkExpr(c.body, catchEnv);
				}

			case EFunction(_, args, _, body):
				var childEnv = new LocalEnv(env);
				for (a in args) {
					if (a.type != null)
						childEnv.set(a.name, a.type);
				}
				checkExpr(body, childEnv);

			case EClass(className, _, methods, _, _, _, _, isExtern):
				if (isExtern == true)
					return;
				var cls = classes.get(className);
				if (cls != null) {
					if (cls.parentName != null) {
						var pInfo = classes.get(cls.parentName);
						if (pInfo != null && pInfo.isExtern) {
							addError('Cannot extend extern class \'${cls.parentName}\'', expr.pos);
						}
					}
					// 1. Override validation
					for (m in methods) {
						var parentMethod = findParentMethod(cls.parentName, m.name);
						#if haxiom_debug_stc
						trace('STC override check class: $className, method: ${m.name}, isOverride: ${m.isOverride}, parentMethod: ${parentMethod != null}');
						#end
						if (m.isOverride) {
							if (parentMethod == null) {
								addError('Method ${m.name} is marked override but no parent class method was found', expr.pos);
							} else if (parentMethod.isAbstract == true) {
								addError('Method ${m.name} overrides an abstract method and must not use the override keyword', expr.pos);
							} else {
								// Signature validation
								if (parentMethod.args.length != m.args.length) {
									addError('Method ${m.name} overrides parent class method but has different argument count', expr.pos);
								} else {
									for (i in 0...m.args.length) {
										var parentArg = parentMethod.args[i];
										var childArg = m.args[i];
										if (Std.string(parentArg.type) != Std.string(childArg.type)) {
											addError('Method ${m.name} overrides parent class method but has incompatible type for argument ${childArg.name}', expr.pos);
										}
									}
								}
								if (Std.string(parentMethod.retType) != Std.string(m.retType)) {
									addError('Method ${m.name} overrides parent class method but has different return type', expr.pos);
								}
							}
						} else {
							if (parentMethod != null && parentMethod.isAbstract != true && m.name != "new") {
								addError('Field ${m.name} overrides parent class field and requires the override keyword', expr.pos);
							}
						}
					}

					// 2. Concrete class abstract implementation validation
					if (!cls.isAbstract) {
						var unimplemented = getUnimplementedAbstractMethods(cls);
						for (absM in unimplemented) {
							addError('Class ${className} must implement abstract method ${absM.methodName} of parent class ${absM.parentName}', expr.pos);
						}
					}
				}

				for (m in methods) {
					if (m.body == null)
						continue; // Abstract methods have no body to check
					var childEnv = new LocalEnv(env);
					childEnv.currentClass = className;
					childEnv.currentMethod = m.name;
					for (a in m.args) {
						if (a.type != null)
							childEnv.set(a.name, a.type);
					}
					checkExpr(m.body, childEnv);
				}
				checkInterfaceImplementationsVisibility(className, expr.pos);

			case EField(objExpr, field) | ESafeField(objExpr, field):
				checkFieldVisibility(objExpr, field, env, expr.pos);
				checkExpr(objExpr, env);

			default:
				// For other expression forms just recurse into sub-expressions
				visitSubExprs(expr, env);
		}
	}

	/**
	 * Like checkExpr, but with an outer type context (e.g. the declared type of a var).
	 * Used to propagate generic type params into enum/class constructor calls.
	 */
	function checkExprWithContext(expr:Expr, env:LocalEnv, contextType:TypeDecl):Void {
		if (expr == null)
			return;
		switch (expr.def) {
			case ECall(calleeExpr, args):
				// Try to handle context-typed enum/class ctor calls
				switch (calleeExpr.def) {
					case EField(objExpr, ctorName):
						switch (objExpr.def) {
							case EIdent(identName):
								// Enum ctor: check with type params from contextType
								if (enums.exists(identName)) {
									var typeParams:Array<TypeDecl> = [];
									if (contextType != null) {
										switch (contextType) {
											case TPath(path, params) if (path.join(".") == identName):
												typeParams = params;
											default:
										}
									}
									checkEnumCtorCall(identName, ctorName, typeParams, args, env, expr.pos);
									for (a in args)
										checkExpr(a, env);
									return;
								}
							default:
						}
					default:
				}
				// Fall through to generic call check
				checkCall(calleeExpr, args, env, expr.pos);

			case ENew(type, args):
				// Pass type params from context if not already specified
				var resolvedType = type;
				if (contextType != null) {
					switch (type) {
						case TPath(path, params) if (params.length == 0):
							switch (contextType) {
								case TPath(ctxPath, ctxParams) if (ctxPath.join(".") == path.join(".")):
									resolvedType = TPath(path, ctxParams);
								default:
							}
						default:
					}
				}
				checkNewExpr(resolvedType, args, env, expr.pos);

			default:
				// No context needed; fall through to normal check
				checkExpr(expr, env);
		}
	}

	function visitSubExprs(expr:Expr, env:LocalEnv):Void {
		switch (expr.def) {
			case EBinop(_, e1, e2):
				checkExpr(e1, env);
				checkExpr(e2, env);
			case EUnop(_, e):
				checkExpr(e, env);
			case EField(e, _) | ESafeField(e, _):
				checkExpr(e, env);
			case EArrayDecl(values):
				for (v in values)
					checkExpr(v, env);
			case EObjectDecl(fields):
				for (f in fields)
					checkExpr(f.expr, env);
			case ESwitch(e, cases, defExpr):
				checkExpr(e, env);
				for (c in cases) {
					checkExpr(c.expr, env);
				}
				if (defExpr != null)
					checkExpr(defExpr, env);
			default:
		}
	}

	// -------------------------------------------------------------------------
	// Method call checking
	// -------------------------------------------------------------------------

	function checkCall(calleeExpr:Expr, args:Array<Expr>, env:LocalEnv, pos:Pos):Void {
		switch (calleeExpr.def) {
			case EField(objExpr, methodName):
				checkFieldVisibility(objExpr, methodName, env, pos);
				var objType = inferType(objExpr, env);

				// Detect enum constructor calls: MyEnum.CtorName(args)
				switch (objExpr.def) {
					case EIdent(identName):
						if (enums.exists(identName)) {
							// Infer type params from context (variable declaration type if available)
							checkEnumCtorCall(identName, methodName, [], args, env, pos);
							for (a in args)
								checkExpr(a, env);
							return;
						}
					default:
				}

				if (objType == null) {
					// Still recurse args
					for (a in args)
						checkExpr(a, env);
					return;
				}
				switch (objType) {
					case TPath(path, typeParams):
						var typeName = path.join(".");
						switch (typeName) {
							case "Array":
								// Array<T>: push(T), unshift(T), insert(Int, T), etc.
								var elemType = typeParams.length > 0 ? typeParams[0] : null;
								if (elemType != null && args.length > 0) {
									switch (methodName) {
										case "push" | "unshift":
											var argType = inferType(args[0], env);
											checkCompatibility(argType, elemType, env, args[0].pos, 'Array.${methodName}');
										case "insert" if (args.length >= 2):
											var argType = inferType(args[1], env);
											checkCompatibility(argType, elemType, env, args[1].pos, 'Array.insert');
										default:
									}
								}

							case "List" | "haxe.ds.List":
								// List<T>: add(T), push(T)
								var elemType = typeParams.length > 0 ? typeParams[0] : null;
								if (elemType != null && args.length > 0) {
									switch (methodName) {
										case "add" | "push":
											var argType = inferType(args[0], env);
											checkCompatibility(argType, elemType, env, args[0].pos, 'List.${methodName}');
										default:
									}
								}

							case "Map" | "haxe.ds.Map" | "haxe.ds.StringMap" | "haxe.ds.IntMap":
								// Map<K,V>: set(K, V)
								var keyType = typeParams.length > 0 ? typeParams[0] : null;
								var valType = typeParams.length > 1 ? typeParams[1] : null;
								if (methodName == "set" && args.length >= 2) {
									if (keyType != null) {
										var argType = inferType(args[0], env);
										checkCompatibility(argType, keyType, env, args[0].pos, 'Map.set (key)');
									}
									if (valType != null) {
										var argType = inferType(args[1], env);
										checkCompatibility(argType, valType, env, args[1].pos, 'Map.set (value)');
									}
								}

							default:
								// Check user-defined class method calls
								if (classes.exists(typeName)) {
									var cls = classes.get(typeName);
									if (cls.methods.exists(methodName)) {
										var method = cls.methods.get(methodName);
										// Build generic bindings from caller type params vs class params
										var bindings = buildGenericBindings(cls.params, typeParams, env, pos);
										checkMethodArgs(method.args, args, env, bindings, methodName, pos);
									}
								}
								// Check enum constructor calls via typed var: var x:MyEnum = MyEnum.Ctor(...)
								if (enums.exists(typeName)) {
									checkEnumCtorCall(typeName, methodName, typeParams, args, env, pos);
								}
						}
					default:
				}
				// Recurse into args
				for (a in args)
					checkExpr(a, env);

			default:
				// Recurse into callee and args
				checkExpr(calleeExpr, env);
				for (a in args)
					checkExpr(a, env);
		}
	}

	function checkMethodArgs(params:Array<FunctionArg>, args:Array<Expr>, env:LocalEnv, bindings:Map<String, TypeDecl>, methodName:String, pos:Pos):Void {
		for (i in 0...params.length) {
			if (i >= args.length)
				break;
			var expectedType = params[i].type;
			if (expectedType == null)
				continue;
			expectedType = applyBindings(expectedType, bindings);
			var argType = inferType(args[i], env);
			checkCompatibility(argType, expectedType, env, args[i].pos, '${methodName} argument ${i + 1}');
		}
	}

	// -------------------------------------------------------------------------
	// ENew checking
	// -------------------------------------------------------------------------

	function checkNewExpr(type:TypeDecl, args:Array<Expr>, env:LocalEnv, pos:Pos):Void {
		switch (type) {
			case TPath(path, typeParams):
				var typeName = path.join(".");
				if (classes.exists(typeName)) {
					var cls = classes.get(typeName);
					if (cls.isAbstract) {
						addError('Cannot instantiate abstract class ${typeName}', pos);
					}
					var bindings = buildGenericBindings(cls.params, typeParams, env, pos);
					if (cls.ctorArgs != null && cls.ctorArgs.length > 0) {
						for (i in 0...cls.ctorArgs.length) {
							if (i >= args.length)
								break;
							var expectedType = cls.ctorArgs[i].type;
							if (expectedType == null)
								continue;
							expectedType = applyBindings(expectedType, bindings);
							// Skip Null<T> wrapper
							expectedType = unwrapNull(expectedType);
							if (expectedType == null)
								continue;
							var argType = inferType(args[i], env);
							checkCompatibility(argType, expectedType, env, args[i].pos, 'new ${typeName} argument ${i + 1}');
						}
					}
				}
			default:
		}
		for (a in args)
			checkExpr(a, env);
	}

	// -------------------------------------------------------------------------
	// Type inference
	// -------------------------------------------------------------------------

	function inferType(expr:Expr, env:LocalEnv):TypeDecl {
		if (expr == null)
			return null;
		switch (expr.def) {
			case EValue(v):
				if (v == null)
					return null;
				if (Std.isOfType(v, Bool))
					return TPath(["Bool"], []);
				if (Std.isOfType(v, Int))
					return TPath(["Int"], []);
				if (Std.isOfType(v, Float))
					return TPath(["Float"], []);
				if (Std.isOfType(v, String))
					return TPath(["String"], []);
				return null;

			case EEReg(pattern, flags):
				return TPath(["EReg"], []);

			case EIdent(name):
				if (env.exists(name)) {
					return env.get(name);
				}
				if (classes.exists(name)) {
					return TPath([name], []);
				}
				return null;

			case EVar(name, type, initExpr, _, _):
				if (type != null)
					return type;
				if (initExpr != null)
					return inferType(initExpr, env);
				return null;

			case EArrayDecl(values):
				if (values.length > 0) {
					var elemType = inferType(values[0], env);
					return TPath(["Array"], elemType != null ? [elemType] : []);
				}
				return TPath(["Array"], []);

			case ENew(type, _):
				return type;

			case ECall(e, args):
				// Try to infer type of method calls
				return inferCallType(e, args, env);

			case EField(objExpr, field):
				// For field access, try to resolve from struct type
				var objType = inferType(objExpr, env);
				return inferFieldType(objType, field, env);

			case EObjectDecl(fields):
				var anonFields = [
					for (f in fields)
						{
							name: f.name,
							type: inferType(f.expr, env),
							opt: false
						}
				];
				return TAnonymous(anonFields);

			case EBlock(exprs):
				if (exprs.length > 0)
					return inferType(exprs[exprs.length - 1], env);
				return null;

			case EIf(_, e1, e2):
				var t1 = inferType(e1, env);
				if (t1 != null)
					return t1;
				if (e2 != null)
					return inferType(e2, env);
				return null;

			case ECast(_, type):
				return type;

			default:
				return null;
		}
	}

	function inferCallType(calleeExpr:Expr, args:Array<Expr>, env:LocalEnv):TypeDecl {
		switch (calleeExpr.def) {
			case EField(obj, field):
				if (field == "await" && obj != null) {
					switch (obj.def) {
						case EIdent("HaxiomHost"):
							if (args.length == 1) {
								var argType = inferType(args[0], env);
								if (argType != null) {
									switch (argType) {
										case TPath(path, typeParams):
											var typeName = path.join(".");
											if ((typeName == "Future" || typeName == "haxiom.guest.Future" || typeName == "haxiom.Future") && typeParams.length > 0) {
												return typeParams[0];
											}
										default:
									}
									return argType;
								}
							}
							return null;
						default:
					}
				}
			default:
		}
		switch (calleeExpr.def) {
			case EField(objExpr, methodName):
				var objType = inferType(objExpr, env);
				if (objType == null)
					return null;
				switch (objType) {
					case TPath(path, typeParams):
						var typeName = path.join(".");
						switch (typeName) {
							case "Array":
								switch (methodName) {
									case "pop" | "shift": return typeParams.length > 0 ? typeParams[0] : null;
									case "filter" | "map" | "copy": return objType;
									case "join": return TPath(["String"], []);
									case "length": return TPath(["Int"], []);
									default: return null;
								}
							case "Map" | "haxe.ds.Map":
								switch (methodName) {
									case "get": return typeParams.length > 1 ? typeParams[1] : null;
									case "keys": return TPath(["Iterator"], typeParams.length > 0 ? [typeParams[0]] : []);
									default: return null;
								}
							default:
								if (classes.exists(typeName)) {
									var cls = classes.get(typeName);
									if (cls.methods.exists(methodName)) {
										var bindings = buildGenericBindings(cls.params, typeParams, env);
										var retType = cls.methods.get(methodName).retType;
										if (retType != null)
											return applyBindings(retType, bindings);
									}
								}
								return null;
						}
					default:
						return null;
				}
			default:
				return null;
		}
	}

	function inferFieldType(objType:TypeDecl, field:String, env:LocalEnv):TypeDecl {
		if (objType == null)
			return null;
		switch (objType) {
			case TFun(args, ret):
				if (field == "bind") {
					return TPath(["Dynamic"], []);
				}
				return null;
			case TAnonymous(fields):
				for (f in fields) {
					if (f.name == field)
						return f.type;
				}
				return null;
			case TPath(path, typeParams):
				var typeName = path.join(".");
				// Resolve typedef
				if (typedefs.exists(typeName)) {
					var tdef = typedefs.get(typeName);
					var resolved = resolveTypedef(tdef, typeParams);
					return inferFieldType(resolved, field, env);
				}
				// Resolve class field
				if (classes.exists(typeName)) {
					var cls = classes.get(typeName);
					if (cls.fields.exists(field)) {
						var bindings = buildGenericBindings(cls.params, typeParams, env);
						return applyBindings(cls.fields.get(field).type, bindings);
					}
				}
				return null;
			default:
				return null;
		}
	}

	function inferIteratorElemType(it:Expr, env:LocalEnv):TypeDecl {
		var t = inferType(it, env);
		if (t == null)
			return null;
		switch (t) {
			case TPath(path, params):
				switch (path.join(".")) {
					case "Array" | "List" | "haxe.ds.List":
						return params.length > 0 ? params[0] : null;
					case "Iterator" | "Iterable":
						return params.length > 0 ? params[0] : null;
					default: return null;
				}
			default:
				return null;
		}
	}

	// -------------------------------------------------------------------------
	// Type compatibility
	// -------------------------------------------------------------------------

	function checkCompatibility(src:TypeDecl, dst:TypeDecl, env:LocalEnv, pos:Pos, context:String):Void {
		if (src == null || dst == null)
			return;
		if (!isCompatible(src, dst, env)) {
			var ctx = context != null ? ' in ${context}' : '';
			throw new CompileException('Type mismatch${ctx}: expected ${typeStr(dst)} but got ${typeStr(src)}', pos != null ? pos.line : 1,
				pos != null ? pos.col : 1, pos != null ? pos.file : "script");
		}
	}

	function isCompatible(src:TypeDecl, dst:TypeDecl, env:LocalEnv):Bool {
		if (src == null || dst == null)
			return true;

		switch [src, dst] {
			case [_, TPath(["Dynamic"], _)] | [TPath(["Dynamic"], _), _]:
				return true;

			case [_, TPath([dstName], [])] if (![
				"Bool",
				"Int",
				"Float",
				"String",
				"Void",
				"Dynamic",
				"Array",
				"Map",
				"List",
				"Null",
				"Iterator",
				"Iterable"
			].contains(dstName) && !classes.exists(dstName) && !enums.exists(dstName) && !typedefs.exists(dstName)):
				// Unbound generic type variable (T, E, V, K, etc.) — accept any value
				return true;

			case [TPath(srcPath, srcParams), TPath(dstPath, dstParams)]:
				var sn = srcPath.join(".");
				var dn = dstPath.join(".");
				if (sn == "haxiom.guest.Future") sn = "Future";
				if (dn == "haxiom.guest.Future") dn = "Future";
				// Allow numeric widening Int → Float
				if (dn == "Float" && sn == "Int")
					return true;
				if (dn == "Dynamic")
					return true;
				if (sn != dn)
					return false;
				// Check type params
				for (i in 0...dstParams.length) {
					if (i >= srcParams.length)
						return true; // lenient on unparameterized
					if (!isCompatible(srcParams[i], dstParams[i], env))
						return false;
				}
				return true;

			case [TAnonymous(srcFields), TPath(dstPath, dstParams)]:
				// Check if src anon struct satisfies a typedef or declared type
				var typeName = dstPath.join(".");
				if (typedefs.exists(typeName)) {
					var tdef = typedefs.get(typeName);
					var resolved = resolveTypedef(tdef, dstParams);
					return isCompatible(src, resolved, env);
				}
				return false;

			case [TPath(srcPath, srcParams), TAnonymous(dstFields)]:
				return false;

			case [TAnonymous(srcFields), TAnonymous(dstFields)]:
				// Structural check: src must have all fields required by dst
				var srcMap = new Map<String, TypeDecl>();
				for (f in srcFields)
					srcMap.set(f.name, f.type);
				for (f in dstFields) {
					if (!srcMap.exists(f.name)) {
						if (f.opt == true)
							continue;
						return false;
					}
					if (!isCompatible(srcMap.get(f.name), f.type, env))
						return false;
				}
				return true;

			default:
				return true;
		}
	}

	// -------------------------------------------------------------------------
	// Enum constructor call detection
	// This checks: var x:MyEnum<T> = MyEnum.Fail("hello");
	// which parses as EVar with initExpr = ECall(EField(EIdent("MyEnum"), "Fail"), [...])
	// We handle this in the EVar case when the declared type has an enum behind it.
	// -------------------------------------------------------------------------

	function checkEnumCtorCall(enumName:String, ctorName:String, typeParams:Array<TypeDecl>, args:Array<Expr>, env:LocalEnv, pos:Pos):Void {
		if (!enums.exists(enumName))
			return;
		var ei = enums.get(enumName);
		if (!ei.constructors.exists(ctorName))
			return;
		var ctorArgs = ei.constructors.get(ctorName);
		var bindings = buildGenericBindings(ei.params, typeParams, env, pos);
		for (i in 0...ctorArgs.length) {
			if (i >= args.length)
				break;
			var expectedType = ctorArgs[i].type;
			if (expectedType == null)
				continue;
			expectedType = applyBindings(expectedType, bindings);
			var argType = inferType(args[i], env);
			checkCompatibility(argType, expectedType, env, args[i].pos, '${enumName}.${ctorName} argument ${i + 1}');
		}
	}

	// -------------------------------------------------------------------------
	// Helpers
	// -------------------------------------------------------------------------

	function resolveTypedef(tdef:TypedefInfo, typeParams:Array<TypeDecl>):TypeDecl {
		var bindings = buildGenericBindings(tdef.params, typeParams);
		return applyBindings(tdef.type, bindings);
	}

	function buildGenericBindings(params:Array<TypeParamDef>, typeArgs:Array<TypeDecl>, env:LocalEnv = null, pos:Pos = null):Map<String, TypeDecl> {
		var m = new Map<String, TypeDecl>();
		if (params == null || typeArgs == null)
			return m;
		for (i in 0...params.length) {
			if (i < typeArgs.length) {
				var pDef = params[i];
				var actualType = typeArgs[i];
				m.set(pDef.name, actualType);
				if (pDef.constraint != null && env != null) {
					var expectedConstraint = applyBindings(pDef.constraint, m);
					checkCompatibility(actualType, expectedConstraint, env, pos != null ? pos : {line: 0, col: 0}, 'Type parameter ${pDef.name} constraint');
				}
			}
		}
		return m;
	}

	function applyBindings(type:TypeDecl, bindings:Map<String, TypeDecl>):TypeDecl {
		if (type == null || bindings == null)
			return type;
		switch (type) {
			case TPath(path, params):
				if (path.length == 1 && bindings.exists(path[0])) {
					return bindings.get(path[0]);
				}
				var resolvedParams = [for (p in params) applyBindings(p, bindings)];
				return TPath(path, resolvedParams);
			case TFun(args, ret):
				return TFun([for (a in args) applyBindings(a, bindings)], applyBindings(ret, bindings));
			case TAnonymous(fields):
				return TAnonymous([
					for (f in fields)
						{name: f.name, type: applyBindings(f.type, bindings), opt: f.opt}
				]);
		}
	}

	function unwrapNull(type:TypeDecl):TypeDecl {
		if (type == null)
			return null;
		switch (type) {
			case TPath(path, params):
				if (path.join(".") == "Null" && params.length > 0)
					return params[0];
			default:
		}
		return type;
	}

	function typeStr(t:TypeDecl):String {
		if (t == null)
			return "Dynamic";
		switch (t) {
			case TPath(path, params):
				var base = path.join(".");
				if (params.length > 0)
					return base + "<" + params.map(typeStr).join(", ") + ">";
				return base;
			case TFun(args, ret):
				return "(" + args.map(typeStr).join(", ") + ") -> " + typeStr(ret);
			case TAnonymous(fields):
				return "{" + fields.map(f -> f.name + ":" + typeStr(f.type)).join(", ") + "}";
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

	function addError(msg:String, pos:Pos):Void {
		throw new CompileException(msg, pos != null ? pos.line : 1, pos != null ? pos.col : 1, pos != null ? pos.file : "script");
	}

	function isClassIdentifier(expr:Expr):Bool {
		switch (expr.def) {
			case EIdent(name):
				return classes.exists(name);
			default:
				return false;
		}
	}

	function checkFieldVisibility(objExpr:Expr, field:String, env:LocalEnv, pos:Pos):Void {
		var isStaticAccess = isClassIdentifier(objExpr);
		var typeName:String = null;
		if (isStaticAccess) {
			switch (objExpr.def) {
				case EIdent(name): typeName = name;
				default:
			}
		} else {
			var objType = inferType(objExpr, env);
			if (objType != null) {
				switch (objType) {
					case TPath(path, _): typeName = path.join(".");
					default:
				}
			}
		}
		if (typeName != null && classes.exists(typeName)) {
			var cls = classes.get(typeName);
			var isPublic = true;
			var isStatic = false;
			var found = false;

			if (cls.fields.exists(field)) {
				var f = cls.fields.get(field);
				isPublic = f.isPublic;
				isStatic = f.isStatic;
				found = true;
			} else if (cls.methods.exists(field)) {
				var m = cls.methods.get(field);
				isPublic = m.isPublic;
				isStatic = m.isStatic;
				found = true;
			}
			if (found) {
				// 1. Static vs Instance validation
				if (isStaticAccess && !isStatic) {
					addError('Cannot access instance member ${field} as static on ${typeName}', pos);
				}

				// 2. Private visibility validation
				if (!isPublic) {
					var hasBypass = false;
					if (env.currentClass != null) {
						var activeCls = classes.get(env.currentClass);
						if (activeCls != null) {
							// Check active class metadata
							if (checkPrivateAccessBypass(activeCls.meta, typeName, field, true)) {
								hasBypass = true;
							}
							// Check active method metadata
							if (env.currentMethod != null) {
								var activeM = activeCls.methods.get(env.currentMethod);
								if (activeM != null && checkPrivateAccessBypass(activeM.meta, typeName, field, true)) {
									hasBypass = true;
								}
							}
						}
						// Check target class @:allow metadata
						var targetCls = classes.get(typeName);
						if (targetCls != null) {
							if (checkPrivateAccessBypass(targetCls.meta, env.currentClass, env.currentMethod, false)) {
								hasBypass = true;
							}
						}
					}
					if (!hasBypass) {
						if (env.currentClass == null || (!isSubclassOfName(env.currentClass, typeName) && !isSubclassOfName(typeName, env.currentClass))) {
							addError('Cannot access private member ${field} of class ${typeName}', pos);
						}
					}
				}
			}
		}
	}

	function findParentMethod(parentName:Null<String>, methodName:String):Dynamic {
		if (parentName == null)
			return null;
		if (classes.exists(parentName)) {
			var pCls = classes.get(parentName);
			if (pCls.methods.exists(methodName)) {
				return pCls.methods.get(methodName);
			}
			return findParentMethod(pCls.parentName, methodName);
		}
		return null;
	}

	function getUnimplementedAbstractMethods(cls:ClassInfo):Array<{methodName:String, parentName:String}> {
		var unimplemented = [];
		var currentParent = cls.parentName;
		var abstractMethods = new Map<String, String>();

		while (currentParent != null && classes.exists(currentParent)) {
			var pCls = classes.get(currentParent);
			for (mName in pCls.methods.keys()) {
				var m = pCls.methods.get(mName);
				if (m.isAbstract) {
					if (!abstractMethods.exists(mName)) {
						abstractMethods.set(mName, currentParent);
					}
				}
			}
			currentParent = pCls.parentName;
		}

		for (mName in abstractMethods.keys()) {
			var implemented = false;
			var current:ClassInfo = cls;
			while (current != null) {
				if (current.methods.exists(mName)) {
					var m = current.methods.get(mName);
					if (!m.isAbstract) {
						implemented = true;
						break;
					}
				}
				if (current.parentName != null && classes.exists(current.parentName)) {
					current = classes.get(current.parentName);
				} else {
					break;
				}
			}
			if (!implemented) {
				unimplemented.push({methodName: mName, parentName: abstractMethods.get(mName)});
			}
		}

		return unimplemented;
	}

	function getExprPath(e:Expr):Null<Array<String>> {
		if (e == null)
			return null;
		switch (e.def) {
			case EIdent(name):
				return [name];
			case EField(objExpr, field):
				var sub = getExprPath(objExpr);
				if (sub != null) {
					return sub.concat([field]);
				}
			default:
		}
		return null;
	}

	function checkPrivateAccessBypass(metaList:Null<Array<{name:String, params:Array<Expr>}>>, targetTypeName:String, fieldName:String, isAccessMode:Bool):Bool {
		if (metaList == null)
			return false;
		for (m in metaList) {
			var isBypassMeta = (isAccessMode && (m.name == ":access" || m.name == "access")) ||
			                   (!isAccessMode && (m.name == ":allow" || m.name == "allow"));
			if (isBypassMeta) {
				if (m.params != null && m.params.length > 0) {
					var path = getExprPath(m.params[0]);
					if (path != null) {
						var pathStr = path.join(".");
						if (pathStr == targetTypeName || pathStr == targetTypeName + "." + fieldName) {
							return true;
						}
					}
				}
			} else if (m.name == ":noPrivateAccess" || m.name == "noPrivateAccess") {
				return true;
			}
		}
		return false;
	}

	function hasMeta(meta:Null<Array<{name:String, params:Array<Expr>}>>, name:String):Bool {
		if (meta == null)
			return false;
		for (m in meta) {
			if (m.name == name)
				return true;
		}
		return false;
	}

	function isSubclassOfName(sub:String, parent:String):Bool {
		var curr = sub;
		while (curr != null) {
			if (curr == parent)
				return true;
			if (classes.exists(curr)) {
				curr = classes.get(curr).parentName;
			} else {
				break;
			}
		}
		return false;
	}

	function checkInterfaceImplementationsVisibility(className:String, pos:Pos):Void {
		if (!classes.exists(className)) return;
		var cls = classes.get(className);
		
		var allItfMethods = new Map<String, Bool>();
		var allItfFields = new Map<String, Bool>();
		var visitedItf = new Map<String, Bool>();

		function collectItfMembers(itfName:String) {
			if (visitedItf.exists(itfName)) return;
			visitedItf.set(itfName, true);
			if (classes.exists(itfName)) {
				var itf = classes.get(itfName);
				for (mKey in itf.methods.keys()) {
					allItfMethods.set(mKey, true);
				}
				for (fKey in itf.fields.keys()) {
					allItfFields.set(fKey, true);
				}
				if (itf.parentName != null) {
					collectItfMembers(itf.parentName);
				}
			}
		}

		for (itfName in cls.interfaces) {
			collectItfMembers(itfName);
		}

		for (mName in allItfMethods.keys()) {
			if (cls.methods.exists(mName)) {
				var m = cls.methods.get(mName);
				if (!m.isPublic) {
					addError('Method ${className}.${mName} must be public to implement interface', pos);
				}
			}
		}
		for (fName in allItfFields.keys()) {
			if (cls.fields.exists(fName)) {
				var f = cls.fields.get(fName);
				if (!f.isPublic) {
					addError('Field ${className}.${fName} must be public to implement interface', pos);
				}
			}
		}
	}
}

// -----------------------------------------------------------------------------
// Local type environment (variable -> declared TypeDecl)
// -----------------------------------------------------------------------------

@:allow(haxiom)
class LocalEnv {
	var parent:LocalEnv;
	var vars:Map<String, TypeDecl> = new Map();
	public var currentClass:Null<String> = null;
	public var currentMethod:Null<String> = null;

	function new(?parent:LocalEnv) {
		this.parent = parent;
		if (parent != null) {
			this.currentClass = parent.currentClass;
			this.currentMethod = parent.currentMethod;
		}
	}

	function set(name:String, type:TypeDecl):Void {
		vars.set(name, type);
	}

	function get(name:String):TypeDecl {
		if (vars.exists(name))
			return vars.get(name);
		if (parent != null)
			return parent.get(name);
		return null;
	}

	function exists(name:String):Bool {
		if (vars.exists(name))
			return true;
		if (parent != null)
			return parent.exists(name);
		return false;
	}
}

// -----------------------------------------------------------------------------
// Lightweight compile-time class/enum/typedef metadata
// -----------------------------------------------------------------------------

@:allow(haxiom)
class ClassInfo {
	var name:String;
	var params:Array<TypeParamDef>;
	var isAbstract:Bool = false;
	var isExtern:Bool = false;
	var parentName:Null<String> = null;
	var interfaces:Array<String> = [];
	var ctorArgs:Array<FunctionArg>;
	var methods:Map<String, {
		name:String,
		args:Array<FunctionArg>,
		retType:Null<TypeDecl>,
		body:Expr,
		isStatic:Bool,
		isPublic:Bool,
		?isOverride:Bool,
		?isAbstract:Bool,
		?meta:Array<{name:String, params:Array<Expr>}>,
		?isExtern:Bool
	}> = new Map();
	var fields:Map<String, {type:TypeDecl, isStatic:Bool, isPublic:Bool, ?meta:Array<{name:String, params:Array<Expr>}>, ?isExtern:Bool}> = new Map();
	var meta:Null<Array<{name:String, params:Array<Expr>}>> = null;

	function new(name:String, params:Array<TypeParamDef>) {
		this.name = name;
		this.params = params;
	}
}

@:allow(haxiom)
class EnumInfo {
	var name:String;
	var params:Array<TypeParamDef>;
	var constructors:Map<String, Array<FunctionArg>> = new Map();

	function new(name:String, params:Array<TypeParamDef>) {
		this.name = name;
		this.params = params;
	}
}

@:allow(haxiom)
class TypedefInfo {
	var name:String;
	var type:TypeDecl;
	var params:Array<TypeParamDef>;

	function new(name:String, type:TypeDecl, params:Array<TypeParamDef>) {
		this.name = name;
		this.type = type;
		this.params = params;
	}
}
