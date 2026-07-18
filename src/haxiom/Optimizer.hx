package haxiom;

import haxiom.AST;

@:allow(haxiom)
class Optimizer {
	static function foldConstants(expr:Expr):Expr {
		if (expr == null)
			return null;

		var foldedDef = switch (expr.def) {
			case EValue(v):
				EValue(v);

			case EIdent(v):
				EIdent(v);

			case EEReg(pattern, flags):
				EEReg(pattern, flags);

			case EVar(name, type, e, isFinal, meta):
				EVar(name, type, e == null ? null : foldConstants(e), isFinal, meta);

			case EAssign(target, e):
				EAssign(foldConstants(target), foldConstants(e));

			case EBinop(op, e1, e2):
				var e1_f = foldConstants(e1);
				var e2_f = foldConstants(e2);

				if (op == "&&") {
					switch (e1_f.def) {
						case EValue(v1):
							if (v1 == false || v1 == null) {
								EValue(v1);
							} else {
								e2_f.def;
							}
						default:
							EBinop(op, e1_f, e2_f);
					}
				} else if (op == "||") {
					switch (e1_f.def) {
						case EValue(v1):
							if (v1 != false && v1 != null) {
								EValue(v1);
							} else {
								e2_f.def;
							}
						default:
							EBinop(op, e1_f, e2_f);
					}
				} else if (op == "??") {
					switch (e1_f.def) {
						case EValue(v1):
							if (v1 != null) {
								EValue(v1);
							} else {
								e2_f.def;
							}
						default:
							EBinop(op, e1_f, e2_f);
					}
				} else if (op == "?") {
					switch (e1_f.def) {
						case EValue(condVal):
							switch (e2_f.def) {
								case EBinop(":", left, right):
									if (condVal != false && condVal != null) {
										left.def;
									} else {
										right.def;
									}
								default:
									EBinop(op, e1_f, e2_f);
							}
						default:
							EBinop(op, e1_f, e2_f);
					}
				} else {
					switch [e1_f.def, e2_f.def] {
						case [EValue(v1), EValue(v2)]:
							try {
								var binopRes:Dynamic = switch (op) {
									case "+":
										if (Std.isOfType(v1, String) || Std.isOfType(v2, String)) {
											Std.string(v1) + Std.string(v2);
										} else {
											(v1 : Float) + (v2 : Float);
										}
									case "-": (v1 : Float) - (v2 : Float);
									case "*": (v1 : Float) * (v2 : Float);
									case "/":
										if ((v2 : Float) == 0)
											throw "DivByZero";
										(v1 : Float) / (v2 : Float);
									case "%":
										if ((v2 : Float) == 0)
											throw "ModByZero";
										(v1 : Float) % (v2 : Float);
									case "==": v1 == v2;
									case "!=": v1 != v2;
									case "<": (v1 : Float) < (v2 : Float);
									case "<=": (v1 : Float) <= (v2 : Float);
									case ">": (v1 : Float) > (v2 : Float);
									case ">=": (v1 : Float) >= (v2 : Float);
									case "&": (v1 : Int) & (v2 : Int);
									case "^": (v1 : Int) ^ (v2 : Int);
									case "<<": (v1 : Int) << (v2 : Int);
									case ">>": (v1 : Int) >> (v2 : Int);
									case ">>>": (v1 : Int) >>> (v2 : Int);
									default:
										throw "UnsupportedOp";
								};
								EValue(binopRes);
							} catch (e:Dynamic) {
								EBinop(op, e1_f, e2_f);
							}
						default:
							EBinop(op, e1_f, e2_f);
					}
				}

			case EUnop(op, e):
				var e_f = foldConstants(e);
				if (op != "++" && op != "--" && op != "post++" && op != "post--") {
					switch (e_f.def) {
						case EValue(val):
							try {
								var unopRes:Dynamic = switch (op) {
									case "!":
										var boolVal = (val != false && val != null);
										!boolVal;
									case "-":
										-(val : Float);
									case "~":
										~(val : Int);
									default:
										throw "UnsupportedOp";
								};
								EValue(unopRes);
							} catch (err:Dynamic) {
								EUnop(op, e_f);
							}
						default:
							EUnop(op, e_f);
					}
				} else {
					EUnop(op, e_f);
				}

			case EField(e, field):
				EField(foldConstants(e), field);

			case ECall(e, args):
				ECall(foldConstants(e), args.map(foldConstants));

			case EArrayDecl(values):
				EArrayDecl(values.map(foldConstants));

			case EObjectDecl(fields):
				EObjectDecl(fields.map(f -> {name: f.name, expr: foldConstants(f.expr)}));

			case EMapDecl(values):
				EMapDecl(values.map(v -> {key: foldConstants(v.key), value: foldConstants(v.value)}));

			case EClass(name, fields, methods, parent, interfaces, params, meta):
				var foldedFields = fields.map(f -> {
					name: f.name,
					type: f.type,
					expr: f.expr == null ? null : foldConstants(f.expr),
					isStatic: f.isStatic,
					isPublic: f.isPublic,
					isFinal: f.isFinal,
					property: f.property,
					meta: f.meta
				});
				var foldedMethods = methods.map(m -> {
					name: m.name,
					args: m.args,
					retType: m.retType,
					body: m.body == null ? null : foldConstants(m.body),
					isStatic: m.isStatic,
					isPublic: m.isPublic,
					isOverride: m.isOverride,
					isAbstract: m.isAbstract,
					meta: m.meta
				});
				EClass(name, foldedFields, foldedMethods, parent, interfaces, params, meta);

			case EBlock(exprs):
				EBlock(exprs.map(foldConstants));

			case EFunction(name, args, retType, body):
				EFunction(name, args, retType, foldConstants(body));

			case EIf(cond, e1, e2):
				var cond_f = foldConstants(cond);
				switch (cond_f.def) {
					case EValue(condVal):
						if (condVal != false && condVal != null) {
							foldConstants(e1).def;
						} else if (e2 != null) {
							foldConstants(e2).def;
						} else {
							EValue(null);
						}
					default:
						EIf(cond_f, foldConstants(e1), e2 == null ? null : foldConstants(e2));
				}

			case EWhile(cond, e):
				EWhile(foldConstants(cond), foldConstants(e));

			case EDoWhile(cond, e):
				EDoWhile(foldConstants(cond), foldConstants(e));

			case EFor(v, it, e):
				EFor(v, foldConstants(it), foldConstants(e));

			case ESwitch(e, cases, defExpr):
				var foldedCases = cases.map(c -> {
					values: c.values.map(foldConstants),
					guard: c.guard == null ? null : foldConstants(c.guard),
					expr: foldConstants(c.expr)
				});
				ESwitch(foldConstants(e), foldedCases, defExpr == null ? null : foldConstants(defExpr));

			case EReturn(e):
				EReturn(e == null ? null : foldConstants(e));

			case EBreak:
				EBreak;

			case EContinue:
				EContinue;

			case EPackage(path):
				EPackage(path);

			case EImport(path, alias):
				EImport(path, alias);

			case EUsing(path):
				EUsing(path);

			case EThrow(e):
				EThrow(foldConstants(e));

			case ETry(tryExpr, catches):
				var foldedCatches = catches.map(c -> {
					pattern: foldConstants(c.pattern),
					type: c.type,
					guard: c.guard == null ? null : foldConstants(c.guard),
					body: foldConstants(c.body)
				});
				ETry(foldConstants(tryExpr), foldedCatches);

			case ECast(e, type):
				ECast(foldConstants(e), type);

			case EMeta(meta, e):
				EMeta(meta, foldConstants(e));

			case EInterface(name, fields, methods, parents, params, meta):
				var foldedFields = fields.map(f -> {
					name: f.name,
					type: f.type,
					property: f.property,
					meta: f.meta
				});
				var foldedMethods = methods.map(m -> {
					name: m.name,
					args: m.args,
					retType: m.retType,
					body: m.body == null ? null : foldConstants(m.body),
					meta: m.meta
				});
				EInterface(name, foldedFields, foldedMethods, parents, params, meta);

			case EEnum(name, constructors, params):
				EEnum(name, constructors, params);

			case ESafeField(e, field):
				ESafeField(foldConstants(e), field);

			case ENew(type, args):
				ENew(type, args.map(foldConstants));

			case EAbstract(name, underlyingType, fields, methods, params, meta):
				var foldedFields = fields.map(f -> {
					name: f.name,
					type: f.type,
					expr: f.expr == null ? null : foldConstants(f.expr),
					isStatic: f.isStatic,
					isPublic: f.isPublic,
					isFinal: f.isFinal,
					property: f.property,
					meta: f.meta
				});
				var foldedMethods = methods.map(m -> {
					name: m.name,
					args: m.args,
					retType: m.retType,
					body: foldConstants(m.body),
					isStatic: m.isStatic,
					isPublic: m.isPublic,
					meta: m.meta
				});
				EAbstract(name, underlyingType, foldedFields, foldedMethods, params, meta);

			case ETypedef(name, type, params):
				ETypedef(name, type, params);
		};

		return {def: foldedDef, pos: expr.pos};
	}

	// =========================================================================
	// Dead Code Elimination (DCE)
	// =========================================================================

	/**
	 * Entry point for the DCE pass. Returns a pruned copy of the AST with:
	 *   - Unreachable statements after return/throw/break/continue removed
	 *   - Unused pure local variables removed
	 *   - Pure expression-statements (no side effects) removed
	 *   - Unused private/static class methods removed
	 *
	 * Runs after foldConstants so constant-folded branches are already resolved.
	 */
	static var globalUsages:Map<String, Int>;
	static var keepSubClassNames:Map<String, Bool> = new Map();

	static function getTypeName(t:TypeDecl):Null<String> {
		if (t == null) return null;
		switch (t) {
			case TPath(path, _):
				return path[path.length - 1];
			default:
				return null;
		}
	}

	static function collectClasses(expr:Expr, classes:Array<Expr>):Void {
		if (expr == null) return;
		switch (expr.def) {
			case EClass(_, _, _, _, _, _, _):
				classes.push(expr);
			case EBlock(exprs):
				for (e in exprs) collectClasses(e, classes);
			default:
		}
	}

	static function processKeepSub(expr:Expr):Void {
		var classesList = [];
		collectClasses(expr, classesList);

		var parentToChildren = new Map<String, Array<String>>();
		var keepSubClasses = new Map<String, Bool>();

		for (cExpr in classesList) {
			switch (cExpr.def) {
				case EClass(name, _, _, parent, _, _, meta):
					var parentName = getTypeName(parent);
					if (parentName != null) {
						if (!parentToChildren.exists(parentName)) {
							parentToChildren.set(parentName, []);
						}
						parentToChildren.get(parentName).push(name);
					}
					if (meta != null) {
						for (m in meta) {
							if (m.name == ":keepSub" || m.name == "keepSub") {
								keepSubClasses.set(name, true);
								break;
							}
						}
					}
				default:
			}
		}

		keepSubClassNames = new Map();
		function propagateKeepSub(clsName:String) {
			keepSubClassNames.set(clsName, true);
			var children = parentToChildren.get(clsName);
			if (children != null) {
				for (child in children) {
					if (!keepSubClassNames.exists(child)) {
						propagateKeepSub(child);
					}
				}
			}
		}

		for (k in keepSubClasses.keys()) {
			propagateKeepSub(k);
		}
	}

	static function eliminateDeadCode(expr:Expr):Expr {
		if (expr == null)
			return null;
		globalUsages = new Map();
		collectUsages(expr, globalUsages);
		processKeepSub(expr);
		return dceExpr(expr);
	}

	static function dceExpr(expr:Expr):Expr {
		if (expr == null)
			return null;
		switch (expr.def) {
			case EBlock(exprs):
				// Prune using global usages
				var pruned = pruneBlock(exprs, globalUsages);
				// Map children; if nothing changed, return expr unchanged
				var mapped = pruned.map(dceExpr);
				// Check if the block was modified (different length or any child changed)
				var modified = pruned.length != exprs.length;
				if (!modified) {
					for (i in 0...pruned.length) {
						if (mapped[i] != exprs[i]) {
							modified = true;
							break;
						}
					}
				}
				return modified ? {def: EBlock(mapped), pos: expr.pos} : expr;

			case EClass(name, fields, methods, parent, interfaces, params, meta):
				// Keep a method if: public, or named "new", or has @:keep, or its name appears in globalUsages
				var prunedMethods = methods.filter(m -> {
					if (m.isPublic)
						return true;
					if (m.name == "new")
						return true;
					if (m.meta != null) {
						for (meta in m.meta) {
							if (meta.name == ":keep" || meta.name == "keep") {
								return true;
							}
						}
					}
					return globalUsages.exists(m.name);
				});
				// Keep a field if: public, or has @:keep, or its name appears in globalUsages (read/written anywhere)
				var prunedFields = fields.filter(f -> {
					if (f.isPublic)
						return true;
					if (f.meta != null) {
						for (meta in f.meta) {
							if (meta.name == ":keep" || meta.name == "keep") {
								return true;
							}
						}
					}
					return globalUsages.exists(f.name);
				});
				var modified = prunedMethods.length != methods.length || prunedFields.length != fields.length;
				var finalMethods = prunedMethods.map(m -> {
					var newBody = m.body == null ? null : dceExpr(m.body);
					if (newBody != m.body) {
						modified = true;
						return {
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: newBody,
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							isOverride: m.isOverride,
							isAbstract: m.isAbstract,
							meta: m.meta
						};
					}
					return m;
				});
				var finalFieldsMapped = prunedFields.map(f -> {
					if (f.expr == null)
						return f;
					var newExpr = dceExpr(f.expr);
					if (newExpr != f.expr) {
						modified = true;
						return {
							name: f.name,
							type: f.type,
							expr: newExpr,
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							isFinal: f.isFinal,
							property: f.property,
							meta: f.meta
						};
					}
					return f;
				});
				return modified ? {def: EClass(name, finalFieldsMapped, finalMethods, parent, interfaces, params, meta), pos: expr.pos} : expr;

			case EFunction(name, args, retType, body):
				var newBody = dceExpr(body);
				return newBody != body ? {def: EFunction(name, args, retType, newBody), pos: expr.pos} : expr;

			case EIf(cond, e1, e2):
				var nc = dceExpr(cond);
				var n1 = dceExpr(e1);
				var n2 = e2 == null ? null : dceExpr(e2);
				return (nc != cond || n1 != e1 || n2 != e2) ? {def: EIf(nc, n1, n2), pos: expr.pos} : expr;

			case EWhile(cond, e):
				var nc = dceExpr(cond);
				var ne = dceExpr(e);
				return (nc != cond || ne != e) ? {def: EWhile(nc, ne), pos: expr.pos} : expr;

			case EDoWhile(cond, e):
				var nc = dceExpr(cond);
				var ne = dceExpr(e);
				return (nc != cond || ne != e) ? {def: EDoWhile(nc, ne), pos: expr.pos} : expr;

			case EFor(v, it, e):
				var ni = dceExpr(it);
				var ne = dceExpr(e);
				return (ni != it || ne != e) ? {def: EFor(v, ni, ne), pos: expr.pos} : expr;

			case ESwitch(e, cases, defExpr):
				var ne = dceExpr(e);
				var modified = ne != e;
				var newCases = cases.map(c -> {
					var nv = c.values.map(dceExpr);
					var ng = c.guard == null ? null : dceExpr(c.guard);
					var nx = dceExpr(c.expr);
					var caseChanged = ng != c.guard || nx != c.expr;
					if (!caseChanged)
						for (i in 0...c.values.length)
							if (nv[i] != c.values[i]) {
								caseChanged = true;
								break;
							}
					if (caseChanged) {
						modified = true;
						return {values: nv, guard: ng, expr: nx};
					}
					return c;
				});
				var nd = defExpr == null ? null : dceExpr(defExpr);
				if (nd != defExpr)
					modified = true;
				return modified ? {def: ESwitch(ne, newCases, nd), pos: expr.pos} : expr;

			case EReturn(e):
				if (e == null)
					return expr;
				var ne = dceExpr(e);
				return ne != e ? {def: EReturn(ne), pos: expr.pos} : expr;

			case EThrow(e):
				var ne = dceExpr(e);
				return ne != e ? {def: EThrow(ne), pos: expr.pos} : expr;

			case ETry(tryExpr, catches):
				var nt = dceExpr(tryExpr);
				var modified = nt != tryExpr;
				var newCatches = catches.map(c -> {
					var np = dceExpr(c.pattern);
					var ng = c.guard == null ? null : dceExpr(c.guard);
					var nb = dceExpr(c.body);
					if (np != c.pattern || ng != c.guard || nb != c.body) {
						modified = true;
						return {
							pattern: np,
							type: c.type,
							guard: ng,
							body: nb
						};
					}
					return c;
				});
				return modified ? {def: ETry(nt, newCatches), pos: expr.pos} : expr;

			case EVar(name, type, initExpr, isFinal, meta):
				if (initExpr == null)
					return expr;
				var ni = dceExpr(initExpr);
				return ni != initExpr ? {def: EVar(name, type, ni, isFinal, meta), pos: expr.pos} : expr;

			case EAssign(target, e):
				var nt = dceExpr(target);
				var ne = dceExpr(e);
				return (nt != target || ne != e) ? {def: EAssign(nt, ne), pos: expr.pos} : expr;

			case EBinop(op, e1, e2):
				var n1 = dceExpr(e1);
				var n2 = dceExpr(e2);
				return (n1 != e1 || n2 != e2) ? {def: EBinop(op, n1, n2), pos: expr.pos} : expr;

			case EUnop(op, e):
				var ne = dceExpr(e);
				return ne != e ? {def: EUnop(op, ne), pos: expr.pos} : expr;

			case EField(e, field):
				var ne = dceExpr(e);
				return ne != e ? {def: EField(ne, field), pos: expr.pos} : expr;

			case ESafeField(e, field):
				var ne = dceExpr(e);
				return ne != e ? {def: ESafeField(ne, field), pos: expr.pos} : expr;

			case ECall(e, args):
				var ne = dceExpr(e);
				var modified = ne != e;
				var na = args.map(a -> {
					var x = dceExpr(a);
					if (x != a)
						modified = true;
					return x;
				});
				return modified ? {def: ECall(ne, na), pos: expr.pos} : expr;

			case ENew(type, args):
				var modified = false;
				var na = args.map(a -> {
					var x = dceExpr(a);
					if (x != a)
						modified = true;
					return x;
				});
				return modified ? {def: ENew(type, na), pos: expr.pos} : expr;

			case EArrayDecl(values):
				var modified = false;
				var nv = values.map(v -> {
					var x = dceExpr(v);
					if (x != v)
						modified = true;
					return x;
				});
				return modified ? {def: EArrayDecl(nv), pos: expr.pos} : expr;

			case EObjectDecl(fields):
				var modified = false;
				var nf = fields.map(f -> {
					var nx = dceExpr(f.expr);
					if (nx != f.expr) {
						modified = true;
						return {name: f.name, expr: nx};
					}
					return f;
				});
				return modified ? {def: EObjectDecl(nf), pos: expr.pos} : expr;

			case EMapDecl(values):
				var modified = false;
				var nv = values.map(v -> {
					var nk = dceExpr(v.key);
					var nx = dceExpr(v.value);
					if (nk != v.key || nx != v.value) {
						modified = true;
						return {key: nk, value: nx};
					}
					return v;
				});
				return modified ? {def: EMapDecl(nv), pos: expr.pos} : expr;

			case ECast(e, type):
				var ne = dceExpr(e);
				return ne != e ? {def: ECast(ne, type), pos: expr.pos} : expr;

			case EMeta(meta, e):
				var ne = dceExpr(e);
				return ne != e ? {def: EMeta(meta, ne), pos: expr.pos} : expr;

			case EAbstract(name, underlyingType, fields, methods, params, meta):
				var modified = false;
				var nf = fields.map(f -> {
					if (f.expr == null)
						return f;
					var nx = dceExpr(f.expr);
					if (nx != f.expr) {
						modified = true;
						return {
							name: f.name,
							type: f.type,
							expr: nx,
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							isFinal: f.isFinal,
							property: f.property,
							meta: f.meta
						};
					}
					return f;
				});
				var nm = methods.map(m -> {
					var nb = dceExpr(m.body);
					if (nb != m.body) {
						modified = true;
						return {
							name: m.name,
							args: m.args,
							retType: m.retType,
							body: nb,
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							meta: m.meta
						};
					}
					return m;
				});
				return modified ? {def: EAbstract(name, underlyingType, nf, nm, params, meta), pos: expr.pos} : expr;

			// Leaf / structural nodes — always unchanged, return original
			default:
				return expr;
		}
	}

	/**
	 * Recursively collect all identifier names that are READ in expr.
	 * Only tracks reads — writes via EVar declarations are NOT counted here.
	 * Call-site names, field objects, and loop variables are all counted as reads.
	 */
	static function collectUsages(expr:Expr, usages:Map<String, Int>):Void {
		if (expr == null)
			return;
		switch (expr.def) {
			case EIdent(name):
				usages.set(name, (usages.exists(name) ? usages.get(name) : 0) + 1);

			case EVar(_, _, initExpr, _, _):
				// The variable NAME is not a usage of itself — only recurse into init
				if (initExpr != null)
					collectUsages(initExpr, usages);

			case EAssign(target, e):
				// The target is being written to, but we still need to track field/subscript reads
				collectUsages(target, usages);
				collectUsages(e, usages);

			case EBlock(exprs):
				for (e in exprs)
					collectUsages(e, usages);

			case EBinop(_, e1, e2):
				collectUsages(e1, usages);
				collectUsages(e2, usages);

			case EUnop(_, e):
				collectUsages(e, usages);

			case EField(e, field) | ESafeField(e, field):
				usages.set(field, (usages.exists(field) ? usages.get(field) : 0) + 1);
				collectUsages(e, usages);

			case ECall(e, args):
				collectUsages(e, usages);
				for (a in args)
					collectUsages(a, usages);

			case ENew(type, args):
				// Mark the instantiated class name as used so it isn't eliminated as dead
				switch (type) {
					case TPath(path, _) if (path.length > 0):
						var name = path[path.length - 1];
						usages.set(name, (usages.exists(name) ? usages.get(name) : 0) + 1);
					default:
				}
				for (a in args)
					collectUsages(a, usages);

			case EIf(cond, e1, e2):
				collectUsages(cond, usages);
				collectUsages(e1, usages);
				if (e2 != null)
					collectUsages(e2, usages);

			case EWhile(cond, e) | EDoWhile(cond, e):
				collectUsages(cond, usages);
				collectUsages(e, usages);

			case EFor(v, it, e):
				collectUsages(it, usages);
				collectUsages(e, usages);
			// v is a loop binding, not an external usage

			case ESwitch(e, cases, defExpr):
				collectUsages(e, usages);
				for (c in cases) {
					for (val in c.values)
						collectUsages(val, usages);
					if (c.guard != null)
						collectUsages(c.guard, usages);
					collectUsages(c.expr, usages);
				}
				if (defExpr != null)
					collectUsages(defExpr, usages);

			case EReturn(e):
				if (e != null)
					collectUsages(e, usages);

			case EThrow(e):
				collectUsages(e, usages);

			case ETry(tryExpr, catches):
				collectUsages(tryExpr, usages);
				for (c in catches) {
					if (c.guard != null)
						collectUsages(c.guard, usages);
					collectUsages(c.body, usages);
				}

			case EArrayDecl(values):
				for (v in values)
					collectUsages(v, usages);

			case EObjectDecl(fields):
				for (f in fields)
					collectUsages(f.expr, usages);

			case EMapDecl(values):
				for (v in values) {
					collectUsages(v.key, usages);
					collectUsages(v.value, usages);
				}

			case ECast(e, _):
				collectUsages(e, usages);

			case EMeta(_, e):
				collectUsages(e, usages);

			case EFunction(_, _, _, body):
				collectUsages(body, usages);

			case EClass(_, fields, methods, parent, interfaces, _, _):
				if (parent != null) {
					switch (parent) {
						case TPath(path, _) if (path.length > 0):
							var name = path[path.length - 1];
							usages.set(name, (usages.exists(name) ? usages.get(name) : 0) + 1);
						default:
					}
				}
				if (interfaces != null) {
					for (itf in interfaces) {
						switch (itf) {
							case TPath(path, _) if (path.length > 0):
								var name = path[path.length - 1];
								usages.set(name, (usages.exists(name) ? usages.get(name) : 0) + 1);
							default:
						}
					}
				}
				for (f in fields)
					if (f.expr != null)
						collectUsages(f.expr, usages);
				for (m in methods)
					if (m.body != null)
						collectUsages(m.body, usages);

			default:
				// EValue, EBreak, EContinue, EPackage, EImport, EEnum, EInterface, ETypedef — no sub-exprs
		}
	}

	/**
	 * Returns true if an expression has no observable side effects:
	 *   - Pure literals: EValue, EIdent (just a read)
	 *   - Pure arithmetic/logical: EBinop of pure operands (no calls, no assignment ops)
	 *   - Pure unary: EUnop (non-mutating operators only)
	 *   - Pure field/index reads: EField, ESafeField
	 *   - Pure array/object/map literals of pure elements
	 *
	 * Returns false (NOT pure) for:
	 *   - ECall, ENew (may have side effects)
	 *   - EAssign, EUnop(++/--) (mutating)
	 *   - EThrow, EReturn (control flow)
	 */
	static function isPure(expr:Expr):Bool {
		if (expr == null)
			return true;
		return switch (expr.def) {
			case EValue(_): true;
			case EIdent(_): true;
			case EEReg(_, _): true;
			case EField(e, _) | ESafeField(e, _): isPure(e);
			case EBinop(op, e1, e2):
				// Assignment operators are not pure
				if (op == "=" || StringTools.endsWith(op, "=")) false; else isPure(e1) && isPure(e2);
			case EUnop(op, e):
				// ++ and -- are mutating
				if (op == "++" || op == "--" || op == "post++" || op == "post--") false; else isPure(e);
			case EArrayDecl(values): values.length == 0 || values.filter(v -> !isPure(v)).length == 0;
			case EObjectDecl(fields): fields.filter(f -> !isPure(f.expr)).length == 0;
			// Typed cast (cast(x, T)) can throw — NOT pure. Unsafe cast (cast x) without type is pure.
			case ECast(e, type): type == null && isPure(e);
			case EMeta(_, e): isPure(e);
			// Anything else (ECall, ENew, EAssign, EThrow, EReturn, blocks, loops) is NOT pure
			default: false;
		};
	}

	/**
	 * Prune a flat list of block statements:
	 *   1. Stop after the first terminal statement (return/throw/break/continue).
	 *   2. Remove EVar declarations where the declared name is never read (usages == 0)
	 *      AND the initializer expression is pure.
	 *   3. Remove pure expression-statements (no side effects, result discarded).
	 *      SAFETY: Never prune the last expression in a block — it may be the yield value
	 *      of a comprehension or block-expression. Never prune bare EIdent reads — they
	 *      commonly serve as yield values inside for/while comprehension bodies.
	 */
	static function pruneBlock(exprs:Array<Expr>, usages:Map<String, Int>):Array<Expr> {
		var result:Array<Expr> = [];
		for (i in 0...exprs.length) {
			var expr = exprs[i];
			var isLast = (i == exprs.length - 1);
			switch (expr.def) {
				// Terminal statements: include this one and stop
				case EReturn(_) | EThrow(_) | EBreak | EContinue:
					result.push(expr);
					return result; // everything after is unreachable

				// Unused pure variable declaration: eliminate ONLY if:
				//   - it has NO type annotation (untyped init has no runtime type check), AND
				//   - the init is pure (no side effects)
				// If there's a type annotation, the runtime validates the init against the
				// declared type, which can throw — so we must NOT eliminate it.
				case EVar(name, declaredType, initExpr, _, _):
					var useCount = usages.exists(name) ? usages.get(name) : 0;
					var isTyped = declaredType != null;
					var initIsPure = initExpr == null || isPure(initExpr);
					if (useCount == 0 && !isTyped && initIsPure) {
						// Eliminated — untyped, unused, pure init
					} else {
						result.push(expr);
					}

				// Named type declarations (class/typedef/enum/interface): eliminate if never
				// referenced from any other code in this block.
				// Exception: a class with a static public main() is an entry point — always keep.
				// Note: unlike EVar, the isLast guard does NOT apply — type declarations are never
				// used as block return values.
				case EClass(name, _, methods, _, interfaces, _, meta):
					var useCount = usages.exists(name) ? usages.get(name) : 0;
					var hasMain = methods.filter(m -> m.name == "main" && m.isPublic && m.isStatic).length > 0;
					var keep = false;
					if (interfaces != null && interfaces.length > 0)
						keep = true;
					if (keepSubClassNames != null && keepSubClassNames.exists(name)) {
						keep = true;
					}
					if (meta != null) {
						for (m in meta) {
							if (m.name == ":keep" || m.name == "keep" || m.name == ":keepSub" || m.name == "keepSub") {
								keep = true;
								break;
							}
						}
					}
					if (useCount == 0 && !hasMain && !keep) {
						// Eliminated — class never instantiated, extended, or referenced
					} else {
						result.push(expr);
					}

				case ETypedef(name, _, _) | EEnum(name, _, _) | EInterface(name, _, _, _, _, _):
					var useCount = usages.exists(name) ? usages.get(name) : 0;
					if (useCount == 0) {
						// Eliminated — type never referenced
					} else {
						result.push(expr);
					}

				// Bare identifier — could be a comprehension/block yield value; always keep
				case EIdent(_):
					result.push(expr);

				// Pure expression used as a statement: eliminate only if not last
				// (last expression in a block may be the block's return value)
				default:
					if (!isLast && isPure(expr)) {
						// Eliminated — pure expression discarded as statement (not last)
					} else {
						result.push(expr);
					}
			}
		}
		return result;
	}
}
