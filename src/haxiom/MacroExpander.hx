package haxiom;

import haxiom.AST;
import haxiom.Interp;

class MacroExpander {
    /**
     * Scans the AST for class declarations and registers them in the interpreter's scope.
     * This makes macro functions available to be executed during macro expansion.
     */
    public static function registerMacros(expr:Expr, interp:Interp):Void {
        if (expr == null) return;
        
        switch (expr.def) {
            case EBlock(exprs):
                for (e in exprs) {
                    registerMacros(e, interp);
                }
            case EClass(_, _, _, _, _, _, _) | EInterface(_, _, _, _, _, _) | EEnum(_, _, _) | EAbstract(_, _, _, _, _, _) | ETypedef(_, _, _) | EPackage(_) | EImport(_, _) | EUsing(_):
                interp.eval(expr, interp.globals);
            default:
                // No-op for other expressions during macro registration phase
        }
    }

    /**
     * Crawls the AST and expands macro calls.
     */
    public static function expand(expr:Expr, interp:Interp):Expr {
        if (expr == null) return null;

        var expandedDef = switch (expr.def) {
            case EValue(v):
                EValue(v);

            case EIdent(v):
                EIdent(v);

            case EVar(name, type, e, isFinal, meta):
                EVar(name, type, e == null ? null : expand(e, interp), isFinal, meta);

            case EAssign(target, e):
                EAssign(expand(target, interp), expand(e, interp));

            case EBinop(op, e1, e2):
                EBinop(op, expand(e1, interp), expand(e2, interp));

            case EUnop(op, e):
                EUnop(op, expand(e, interp));

            case EField(e, field):
                EField(expand(e, interp), field);

            case ECall(e, args):
                var isMacroCall = false;
                var macroClass:HaxiomClass = null;
                var macroMethodName:String = null;

                switch (e.def) {
                    case EField(objExpr, fieldName):
                        switch (objExpr.def) {
                            case EIdent(className):
                                if (interp.globals.exists(className)) {
                                    var clsVal = interp.globals.get(className);
                                    if (clsVal != null && Std.isOfType(clsVal, HaxiomClass)) {
                                        var cls:HaxiomClass = cast clsVal;
                                        if (cls.methods.exists(fieldName)) {
                                            var method = cls.methods.get(fieldName);
                                            if (method.isStatic && method.meta != null) {
                                                for (m in method.meta) {
                                                    if (m.name == ":haxiom.macro" || m.name == "haxiom.macro") {
                                                        isMacroCall = true;
                                                        macroClass = cls;
                                                        macroMethodName = fieldName;
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            default:
                        }
                    default:
                }

                if (isMacroCall) {
                    var method = macroClass.methods.get(macroMethodName);
                    var boundMethod = interp.bindMethod(null, method);
                    var macroResultExpr:Expr = Reflect.callMethod(null, boundMethod, args);
                    
                    if (macroResultExpr == null) {
                        throw 'Macro $macroMethodName returned null instead of a valid Expr AST node';
                    }
                    if (Reflect.field(macroResultExpr, "def") == null) {
                        throw 'Macro $macroMethodName returned invalid object instead of a valid Expr AST node';
                    }
                    
                    var resolvedExpanded = expand(macroResultExpr, interp);
                    resolvedExpanded.def;
                } else {
                    ECall(expand(e, interp), args.map(arg -> expand(arg, interp)));
                }

            case EArrayDecl(values):
                EArrayDecl(values.map(v -> expand(v, interp)));

            case EObjectDecl(fields):
                EObjectDecl(fields.map(f -> {name: f.name, expr: expand(f.expr, interp)}));

            case EMapDecl(values):
                EMapDecl(values.map(v -> {key: expand(v.key, interp), value: expand(v.value, interp)}));

            case EClass(name, fields, methods, parent, interfaces, params, meta):
                var expandedMethods = methods.map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: expand(m.body, interp),
                    isStatic: m.isStatic,
                    isPublic: m.isPublic,
                    meta: m.meta
                });
                var expandedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    expr: f.expr == null ? null : expand(f.expr, interp),
                    isStatic: f.isStatic,
                    isPublic: f.isPublic,
                    isFinal: f.isFinal,
                    property: f.property,
                    meta: f.meta
                });
                EClass(name, expandedFields, expandedMethods, parent, interfaces, params, meta);

            case EBlock(exprs):
                EBlock(exprs.map(e -> expand(e, interp)));

            case EFunction(name, args, retType, body):
                EFunction(name, args, retType, expand(body, interp));

            case EIf(cond, e1, e2):
                EIf(expand(cond, interp), expand(e1, interp), e2 == null ? null : expand(e2, interp));

            case EWhile(cond, e):
                EWhile(expand(cond, interp), expand(e, interp));

            case EDoWhile(cond, e):
                EDoWhile(expand(cond, interp), expand(e, interp));

            case EFor(v, it, e):
                EFor(v, expand(it, interp), expand(e, interp));

            case ESwitch(e, cases, defExpr):
                var expandedCases = cases.map(c -> {
                    values: c.values.map(val -> expand(val, interp)),
                    guard: c.guard == null ? null : expand(c.guard, interp),
                    expr: expand(c.expr, interp)
                });
                ESwitch(expand(e, interp), expandedCases, defExpr == null ? null : expand(defExpr, interp));

            case EReturn(e):
                EReturn(e == null ? null : expand(e, interp));

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
                EThrow(expand(e, interp));

            case ETry(tryExpr, catches):
                var expandedCatches = catches.map(c -> {
                    pattern: expand(c.pattern, interp),
                    type: c.type,
                    guard: c.guard == null ? null : expand(c.guard, interp),
                    body: expand(c.body, interp)
                });
                ETry(expand(tryExpr, interp), expandedCatches);

            case ECast(e, type):
                ECast(expand(e, interp), type);

            case EMeta(meta, e):
                EMeta(meta, expand(e, interp));

            case EInterface(name, fields, methods, parents, params, meta):
                EInterface(name, fields, methods, parents, params, meta);

            case EEnum(name, constructors, params):
                EEnum(name, constructors, params);

            case ESafeField(e, field):
                ESafeField(expand(e, interp), field);

            case ENew(type, args):
                ENew(type, args.map(arg -> expand(arg, interp)));

            case EAbstract(name, underlyingType, fields, methods, params, meta):
                var expandedMethods = methods.map(m -> {
                    name: m.name,
                    args: m.args,
                    retType: m.retType,
                    body: expand(m.body, interp),
                    isStatic: m.isStatic,
                    isPublic: m.isPublic,
                    meta: m.meta
                });
                var expandedFields = fields.map(f -> {
                    name: f.name,
                    type: f.type,
                    expr: f.expr == null ? null : expand(f.expr, interp),
                    isStatic: f.isStatic,
                    isPublic: f.isPublic,
                    isFinal: f.isFinal,
                    property: f.property,
                    meta: f.meta
                });
                EAbstract(name, underlyingType, expandedFields, expandedMethods, params, meta);

            case ETypedef(name, type, params):
                ETypedef(name, type, params);
        };

        return { def: expandedDef, pos: expr.pos };
    }
}
