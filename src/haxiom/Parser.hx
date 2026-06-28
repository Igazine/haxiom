package haxiom;

import haxiom.AST;

class Parser {
    var tokens:Array<Token>;
    var pos:Int = 0;
    var compCounter:Int = 0;
    var file:String;
    var definedTypes:Map<String, Pos> = new Map();

    function registerType(name:String, pos:Pos) {
        if (definedTypes.exists(name)) {
            var prev = definedTypes.get(name);
            throw new CompileException("Redefinition of class " + name + " (previously defined at line " + prev.line + ", col " + prev.col + ")", pos.line, pos.col, file);
        }
        definedTypes.set(name, pos);
    }

    public function new(tokens:Array<Token>, ?file:String) {
        this.tokens = tokens;
        this.file = file != null ? file : "script";
    }

    public function parse():Expr {
        var exprs = [];
        while (!is(TEof)) {
            skipNewlines();
            if (is(TEof)) break;
            exprs.push(parseStatement());
            skipNewlines();
        }
        return { def: EBlock(exprs), pos: { line: 1, col: 1 } };
    }

    public function parseExprOnly():Expr {
        skipNewlines();
        var e = parseExpr();
        skipNewlines();
        expect(TEof);
        return e;
    }

    function parseStatement():Expr {
        skipNewlines();
        var meta = parseMetadata();
        var t = peek();
        if (t.def == TInline) {
            next();
            t = peek();
            if (t.def != TFunction) {
                throw new CompileException("Expected function after inline modifier", t.pos.line, t.pos.col, file);
            }
        }
        var expr:Expr = null;
        switch (t.def) {
            case TPackage:
                if (meta != null) throw new CompileException("Metadata cannot be attached to a package declaration", t.pos.line, t.pos.col, file);
                next();
                var path = [];
                if (!is(TSemicolon)) {
                    path.push(expectIdent());
                    while (match(TDot)) {
                        path.push(expectIdent());
                    }
                }
                expect(TSemicolon);
                expr = mk(EPackage(path), t.pos);
            case TImport:
                if (meta != null) throw new CompileException("Metadata cannot be attached to an import declaration", t.pos.line, t.pos.col, file);
                next();
                var path = [];
                if (match(TStar)) {
                    path.push("*");
                } else {
                    path.push(expectIdent());
                    while (match(TDot)) {
                        if (match(TStar)) {
                            path.push("*");
                            break;
                        }
                        path.push(expectIdent());
                    }
                }
                var alias = null;
                var nextT = peek();
                switch (nextT.def) {
                    case TIdent("as"):
                        next();
                        alias = expectIdent();
                    default:
                }
                expect(TSemicolon);
                expr = mk(EImport(path, alias), t.pos);
            case TUsing:
                if (meta != null) throw new CompileException("Metadata cannot be attached to a using declaration", t.pos.line, t.pos.col, file);
                next();
                var path = [];
                path.push(expectIdent());
                while (match(TDot)) {
                    path.push(expectIdent());
                }
                expect(TSemicolon);
                expr = mk(EUsing(path), t.pos);
            case TThrow:
                next();
                var e = parseExpr();
                expect(TSemicolon);
                expr = mk(EThrow(e), t.pos);
            case TTry:
                next();
                var tryBody = parseStatement();
                var catches = [];
                while (match(TCatch)) {
                    expect(TParenOpen);
                    var pattern = null;
                    var typeDecl = null;
                    if (isIdent(peek()) && Type.enumIndex(peek(1).def) == Type.enumIndex(TColon)) {
                        var idPos = peek().pos;
                        var name = expectIdent();
                        pattern = mk(EIdent(name), idPos);
                        expect(TColon);
                        typeDecl = parseType();
                    } else {
                        pattern = parseExpr();
                    }
                    var guard = null;
                    if (match(TIf)) {
                        expect(TParenOpen);
                        guard = parseExpr();
                        expect(TParenClose);
                    }
                    expect(TParenClose);
                    var catchBody = parseStatement();
                    catches.push({ pattern: pattern, type: typeDecl, guard: guard, body: catchBody });
                }
                expr = mk(ETry(tryBody, catches), t.pos);
            case TFinal:
                next();
                match(TVar);
                var name = expectIdent();
                var vType = parseOptType();
                var e = null;
                if (match(TAssign)) {
                    e = parseExpr();
                }
                expect(TSemicolon);
                expr = mk(EVar(name, vType, e, true, meta), t.pos);
            case TClass:
                expr = parseClass(meta);
            case TAbstract:
                expr = parseAbstract(meta);
            case TTypedef:
                expr = parseTypedef();
            case TInterface:
                expr = parseInterface(meta);
            case TEnum:
                expr = parseEnum();
            case TVar:
                expr = parseVar(meta);
            case TIf:
                expr = parseIf();
            case TWhile:
                expr = parseWhile();
            case TDo:
                expr = parseDoWhile();
            case TFor:
                expr = parseFor();
            case TSwitch:
                expr = parseSwitch();
            case TReturn:
                next();
                var e = null;
                if (!is(TSemicolon) && !is(TNewline) && !is(TBraceClose)) {
                    e = parseExpr();
                }
                expect(TSemicolon);
                expr = mk(EReturn(e), t.pos);
            case TBreak:
                next();
                expect(TSemicolon);
                expr = mk(EBreak, t.pos);
            case TContinue:
                next();
                expect(TSemicolon);
                expr = mk(EContinue, t.pos);
            case TBraceOpen:
                expr = parseBlock();
            default:
                expr = parseExpr();
                switch (expr.def) {
                    case EFunction(_, _, _, _):
                        match(TSemicolon);
                    default:
                        if (is(TBracketClose) || is(TElse) || is(TCatch) || is(TBraceClose)) {
                            match(TSemicolon);
                        } else {
                            expect(TSemicolon);
                        }
                }
        }
        
        if (meta != null && expr != null) {
            switch (expr.def) {
                case EClass(_, _, _, _, _, _, _): // meta already attached inside class
                case EInterface(_, _, _, _, _, _): // meta already attached inside interface
                case EAbstract(_, _, _, _, _, _): // meta already attached inside abstract
                case EVar(_, _, _, _, _): // meta already attached inside var/final
                default:
                    expr = mk(EMeta(meta, expr), t.pos);
            }
        }
        return expr;
    }

    function parseBlock():Expr {
        var t = expect(TBraceOpen);
        var exprs = [];
        while (!is(TBraceClose) && !is(TEof)) {
            skipNewlines();
            if (is(TBraceClose)) break;
            exprs.push(parseStatement());
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EBlock(exprs), t.pos);
    }

    function checkAndSplitShiftRight() {
        var t = peek();
        switch (t.def) {
            case TShiftRight:
                t.def = TGreater;
                tokens.insert(pos + 1, { def: TGreater, pos: t.pos });
            case TUnsignedShiftRight:
                t.def = TGreater;
                tokens.insert(pos + 1, { def: TGreater, pos: t.pos });
                tokens.insert(pos + 2, { def: TGreater, pos: t.pos });
            default:
        }
    }

    function parseOptParams():Array<String> {
        var params = [];
        if (match(TLess)) {
            params.push(expectIdent());
            while (match(TComma)) {
                params.push(expectIdent());
            }
            checkAndSplitShiftRight();
            expect(TGreater);
        }
        return params;
    }

    function parsePropertyAccessor():String {
        var t = peek();
        switch (t.def) {
            case TIdent(id):
                next();
                return id;
            case TDefault:
                next();
                return "default";
            case TNull:
                next();
                return "null";
            default:
                throw new CompileException("Expected property accessor (identifier, default, or null) but got " + t.def, t.pos.line, t.pos.col, file);
        }
    }

    function parseMetadata():Array<{name:String, params:Array<Expr>}> {
        var meta = [];
        while (match(TAt)) {
            var name = "";
            if (match(TColon)) {
                name = ":" + expectIdent();
            } else {
                name = expectIdent();
            }
            while (match(TDot)) {
                name += "." + expectIdent();
            }
            var params = [];
            if (match(TParenOpen)) {
                if (!is(TParenClose)) {
                    params.push(parseExpr());
                    while (match(TComma)) {
                        params.push(parseExpr());
                    }
                }
                expect(TParenClose);
            }
            meta.push({ name: name, params: params });
            skipNewlines();
        }
        return meta.length > 0 ? meta : null;
    }

    function parseClass(?meta:Array<{name:String, params:Array<Expr>}>):Expr {
        var t = expect(TClass);
        var name = expectIdent();
        registerType(name, t.pos);
        var params = parseOptParams();
        var parent = null;
        if (match(TExtends)) {
            parent = parseType(false);
        }
        var interfaces = [];
        while (match(TImplements)) {
            interfaces.push(parseType(false));
        }
        expect(TBraceOpen);
        skipNewlines();
        
        var fields = [];
        var methods = [];
        
        while (!is(TBraceClose) && !is(TEof)) {
            var fMeta = parseMetadata();
            var isStatic = false;
            var isPublic = false; // Default member visibility is private
            var isFinal = false;
            
            while (true) {
                if (match(TStatic)) {
                    isStatic = true;
                } else if (match(TPublic)) {
                    isPublic = true;
                } else if (match(TPrivate)) {
                    isPublic = false;
                } else if (match(TFinal)) {
                    isFinal = true;
                } else if (match(TInline)) {
                    // Ignore inline modifier
                } else {
                    break;
                }
            }
            
            skipNewlines();
            var memberT = peek();
            if (memberT.def == TVar || isFinal) {
                if (memberT.def == TVar) {
                    next();
                }
                var fName = expectIdent();
                var prop = null;
                if (match(TParenOpen)) {
                    var getM = parsePropertyAccessor();
                    expect(TComma);
                    var setM = parsePropertyAccessor();
                    expect(TParenClose);
                    prop = { get: getM, set: setM };
                }
                var fType = parseOptType();
                var fExpr = null;
                if (match(TAssign)) {
                    fExpr = parseExpr();
                }
                expect(TSemicolon);
                fields.push({ name: fName, type: fType, expr: fExpr, isStatic: isStatic, isPublic: isPublic, isFinal: isFinal, property: prop, meta: fMeta });
            } else if (memberT.def == TFunction) {
                next();
                var mName = "";
                if (match(TNew)) {
                    mName = "new";
                } else {
                    mName = expectIdent();
                }
                var mArgs = parseArgs();
                var mRetType = parseOptType();
                var mBody = parseBlock();
                methods.push({ name: mName, args: mArgs, retType: mRetType, body: mBody, isStatic: isStatic, isPublic: isPublic, meta: fMeta });
            } else {
                throw new CompileException('Unexpected token inside class ${memberT.def}', memberT.pos.line, memberT.pos.col, file);
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EClass(name, fields, methods, parent, interfaces, params, meta), t.pos);
    }

    function parseAbstract(?meta:Array<{name:String, params:Array<Expr>}>):Expr {
        var t = expect(TAbstract);
        var name = expectIdent();
        var params = parseOptParams();
        expect(TParenOpen);
        var underlyingType = parseType();
        expect(TParenClose);
        
        var fromTypes:Array<TypeDecl> = [];
        var toTypes:Array<TypeDecl> = [];
        while (true) {
            var pToken = peek();
            switch (pToken.def) {
                case TIdent("from"):
                    next();
                    fromTypes.push(parseType());
                case TIdent("to"):
                    next();
                    toTypes.push(parseType());
                default:
                    break;
            }
        }

        if (meta == null) meta = [];
        for (fType in fromTypes) {
            meta.push({ name: ":haxiom.fromType", params: [ { def: EValue(typeToString(fType)), pos: t.pos } ] });
        }
        for (tType in toTypes) {
            meta.push({ name: ":haxiom.toType", params: [ { def: EValue(typeToString(tType)), pos: t.pos } ] });
        }
        
        expect(TBraceOpen);
        skipNewlines();
        
        var fields = [];
        var methods = [];
        
        while (!is(TBraceClose) && !is(TEof)) {
            var fMeta = parseMetadata();
            var isStatic = false;
            var isPublic = true; // Abstracts default visibility to public in Haxe
            var isFinal = false;
            
            while (true) {
                if (match(TStatic)) {
                    isStatic = true;
                } else if (match(TPublic)) {
                    isPublic = true;
                } else if (match(TPrivate)) {
                    isPublic = false;
                } else if (match(TFinal)) {
                    isFinal = true;
                } else if (match(TInline)) {
                    // Ignore inline modifier
                } else {
                    break;
                }
            }
            
            skipNewlines();
            var memberT = peek();
            if (memberT.def == TVar || isFinal) {
                if (memberT.def == TVar) {
                    next();
                }
                var fName = expectIdent();
                var prop = null;
                if (match(TParenOpen)) {
                    var getM = parsePropertyAccessor();
                    expect(TComma);
                    var setM = parsePropertyAccessor();
                    expect(TParenClose);
                    prop = { get: getM, set: setM };
                }
                var fType = parseOptType();
                var fExpr = null;
                if (match(TAssign)) {
                    fExpr = parseExpr();
                }
                expect(TSemicolon);
                fields.push({ name: fName, type: fType, expr: fExpr, isStatic: isStatic, isPublic: isPublic, isFinal: isFinal, property: prop, meta: fMeta });
            } else if (memberT.def == TFunction) {
                next();
                var mName = "";
                if (match(TNew)) {
                    mName = "new";
                } else {
                    mName = expectIdent();
                }
                var mArgs = parseArgs();
                var mRetType = parseOptType();
                var mBody = parseBlock();
                methods.push({ name: mName, args: mArgs, retType: mRetType, body: mBody, isStatic: isStatic, isPublic: isPublic, meta: fMeta });
            } else {
                throw new CompileException('Unexpected token inside abstract ${memberT.def}', memberT.pos.line, memberT.pos.col, file);
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EAbstract(name, underlyingType, fields, methods, params, meta), t.pos);
    }

    function parseVar(?meta:Array<{name:String, params:Array<Expr>}>):Expr {
        var t = expect(TVar);
        var name = expectIdent();
        var vType = parseOptType();
        var expr = null;
        if (match(TAssign)) {
            expr = parseExpr();
        }
        expect(TSemicolon);
        return mk(EVar(name, vType, expr, false, meta), t.pos);
    }

    function parseIf():Expr {
        var t = expect(TIf);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        var e1 = parseStatement();
        var e2 = null;
        skipNewlines();
        if (match(TElse)) {
            e2 = parseStatement();
        }
        return mk(EIf(cond, e1, e2), t.pos);
    }

    function parseWhile():Expr {
        var t = expect(TWhile);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        var body = parseStatement();
        return mk(EWhile(cond, body), t.pos);
    }

    function parseDoWhile():Expr {
        var t = expect(TDo);
        var body = parseStatement();
        skipNewlines();
        expect(TWhile);
        expect(TParenOpen);
        var cond = parseExpr();
        expect(TParenClose);
        expect(TSemicolon);
        return mk(EDoWhile(cond, body), t.pos);
    }

    function parseFor():Expr {
        var t = expect(TFor);
        expect(TParenOpen);
        var vName = expectIdent();
        expect(TIn);
        var iterable = parseExpr();
        expect(TParenClose);
        var body = parseStatement();
        return mk(EFor(vName, iterable, body), t.pos);
    }

    function parseSwitch():Expr {
        var t = expect(TSwitch);
        expect(TParenOpen);
        var expr = parseExpr();
        expect(TParenClose);
        expect(TBraceOpen);
        skipNewlines();
        
        var cases = [];
        var defExpr = null;
        
        while (!is(TBraceClose) && !is(TEof)) {
            var caseT = peek();
            if (match(TCase)) {
                var values = [];
                values.push(parseCasePattern());
                while (match(TComma)) {
                    values.push(parseCasePattern());
                }
                var guard = null;
                if (match(TIf)) {
                    guard = parseExpr();
                }
                expect(TColon);
                skipNewlines();
                var cExprs = [];
                while (!is(TCase) && !is(TDefault) && !is(TBraceClose) && !is(TEof)) {
                    cExprs.push(parseStatement());
                    skipNewlines();
                }
                cases.push({ values: values, guard: guard, expr: mk(EBlock(cExprs), caseT.pos) });
            } else if (match(TDefault)) {
                expect(TColon);
                skipNewlines();
                var dExprs = [];
                while (!is(TCase) && !is(TDefault) && !is(TBraceClose) && !is(TEof)) {
                    dExprs.push(parseStatement());
                    skipNewlines();
                }
                defExpr = mk(EBlock(dExprs), caseT.pos);
            } else {
                throw new CompileException('Unexpected token inside switch ${caseT.def}', caseT.pos.line, caseT.pos.col, file);
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(ESwitch(expr, cases, defExpr), t.pos);
    }

    function parseArgs():Array<FunctionArg> {
        expect(TParenOpen);
        var args = [];
        if (!is(TParenClose)) {
            var isRest = match(TDotDotDot);
            match(TQuestion); // skip optional marker
            var name = expectIdent();
            var type = parseOptType();
            args.push({ name: name, type: type, isRest: isRest });
            while (match(TComma)) {
                var nextIsRest = match(TDotDotDot);
                match(TQuestion); // skip optional marker
                var argName = expectIdent();
                var argType = parseOptType();
                args.push({ name: argName, type: argType, isRest: nextIsRest });
            }
        }
        expect(TParenClose);
        return args;
    }

    function parseCasePattern():Expr {
        var e = parseExpr();
        if (match(TMapArrow)) {
            var pat = parseExpr();
            e = mk(EBinop("=>", e, pat), e.pos);
        }
        return e;
    }

    // --- Expression Pratt/Operator Precedence Parser ---
    
    function parseExpr():Expr {
        return parseAssign();
    }

    function parseAssign():Expr {
        var e = parseMapArrow();
        var t = peek();
        if (match(TAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, rhs), t.pos);
        } else if (match(TPlusAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("+", e, rhs), t.pos)), t.pos);
        } else if (match(TMinusAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("-", e, rhs), t.pos)), t.pos);
        } else if (match(TStarAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("*", e, rhs), t.pos)), t.pos);
        } else if (match(TSlashAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("/", e, rhs), t.pos)), t.pos);
        } else if (match(TPercentAssign)) {
            var rhs = parseAssign();
            return mk(EAssign(e, mk(EBinop("%", e, rhs), t.pos)), t.pos);
        }
        return e;
    }

    function parseMapArrow():Expr {
        var e = parseTernary();
        var t = peek();
        if (match(TMapArrow)) {
            var rhs = parseMapArrow();
            return mk(EBinop("=>", e, rhs), t.pos);
        }
        return e;
    }

    function parseTernary():Expr {
        var e = parseCoalesce();
        var t = peek();
        if (match(TQuestion)) {
            var e1 = parseExpr();
            expect(TColon);
            var e2 = parseTernary();
            return mk(EBinop("?", e, mk(EBinop(":", e1, e2), t.pos)), t.pos);
        }
        return e;
    }

    function parseCoalesce():Expr {
        var e = parseOr();
        var t = peek();
        while (match(TDoubleQuestion)) {
            var e2 = parseOr();
            e = mk(EBinop("??", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseOr():Expr {
        var e = parseAnd();
        var t = peek();
        while (match(TOr)) {
            var e2 = parseAnd();
            e = mk(EBinop("||", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseAnd():Expr {
        var e = parseEquality();
        var t = peek();
        while (match(TAnd)) {
            var e2 = parseEquality();
            e = mk(EBinop("&&", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseEquality():Expr {
        var e = parseRelation();
        var t = peek();
        while (is(TEqual) || is(TNotEqual)) {
            var op = match(TEqual) ? "==" : (match(TNotEqual) ? "!=" : throw new CompileException("Expected !=", t.pos.line, t.pos.col, file));
            var e2 = parseRelation();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseRelation():Expr {
        var e = parseInterval();
        var t = peek();
        while (is(TLess) || is(TLessEqual) || is(TGreater) || is(TGreaterEqual) || is(TIn)) {
            var op = "";
            if (match(TLess)) op = "<";
            else if (match(TLessEqual)) op = "<=";
            else if (match(TGreater)) op = ">";
            else if (match(TGreaterEqual)) op = ">=";
            else if (match(TIn)) op = "in";
            
            var e2 = parseInterval();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseInterval():Expr {
        var e = parseShift();
        var t = peek();
        while (match(TDotDotDot)) {
            var e2 = parseShift();
            e = mk(EBinop("...", e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseShift():Expr {
        var e = parseBitwise();
        var t = peek();
        while (is(TShiftLeft) || is(TShiftRight) || is(TUnsignedShiftRight)) {
            var op = "";
            if (match(TShiftLeft)) op = "<<";
            else if (match(TShiftRight)) op = ">>";
            else if (match(TUnsignedShiftRight)) op = ">>>";
            
            var e2 = parseBitwise();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseBitwise():Expr {
        var e = parseAdditive();
        var t = peek();
        while (is(TBitAnd) || is(TBitOr) || is(TBitXor)) {
            var op = "";
            if (match(TBitAnd)) op = "&";
            else if (match(TBitOr)) op = "|";
            else if (match(TBitXor)) op = "^";
            
            var e2 = parseAdditive();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseAdditive():Expr {
        var e = parseMultiplicative();
        var t = peek();
        while (is(TPlus) || is(TMinus)) {
            var op = match(TPlus) ? "+" : { match(TMinus); "-"; };
            var e2 = parseMultiplicative();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseMultiplicative():Expr {
        var e = parseUnary();
        var t = peek();
        while (is(TStar) || is(TSlash) || is(TPercent)) {
            var op = "";
            if (match(TStar)) op = "*";
            else if (match(TSlash)) op = "/";
            else if (match(TPercent)) op = "%";
            
            var e2 = parseUnary();
            e = mk(EBinop(op, e, e2), t.pos);
            t = peek();
        }
        return e;
    }

    function parseUnary():Expr {
        var t = peek();
        if (match(TNot)) {
            return mk(EUnop("!", parseUnary()), t.pos);
        } else if (match(TMinus)) {
            return mk(EUnop("-", parseUnary()), t.pos);
        } else if (match(TBitNot)) {
            return mk(EUnop("~", parseUnary()), t.pos);
        } else if (match(TIncrement)) {
            return mk(EUnop("++", parseUnary()), t.pos);
        } else if (match(TDecrement)) {
            return mk(EUnop("--", parseUnary()), t.pos);
        }
        return parsePostfix();
    }

    function parsePostfix():Expr {
        var e = parsePrimary();
        while (true) {
            var t = peek();
            if (match(TDot)) {
                var field = expectIdent();
                e = mk(EField(e, field), t.pos);
            } else if (match(TQuestionDot)) {
                var field = expectIdent();
                e = mk(ESafeField(e, field), t.pos);
            } else if (is(TParenOpen)) {
                var args = parseCallArgs();
                e = mk(ECall(e, args), t.pos);
            } else if (match(TBracketOpen)) {
                var index = parseExpr();
                expect(TBracketClose);
                e = mk(EBinop("[]", e, index), t.pos);
            } else if (match(TIncrement)) {
                e = mk(EUnop("post++", e), t.pos);
            } else if (match(TDecrement)) {
                e = mk(EUnop("post--", e), t.pos);
            } else {
                break;
            }
        }
        return e;
    }

    function parseCallArgs():Array<Expr> {
        expect(TParenOpen);
        var args = [];
        if (!is(TParenClose)) {
            args.push(parseExpr());
            while (match(TComma)) {
                args.push(parseExpr());
            }
        }
        expect(TParenClose);
        return args;
    }

    function parsePrimary():Expr {
        var t = peek();
        switch (t.def) {
            case TCast:
                next();
                if (match(TParenOpen)) {
                    var e = parseExpr();
                    if (match(TComma)) {
                        var type = parseType();
                        expect(TParenClose);
                        return mk(ECast(e, type), t.pos);
                    } else {
                        expect(TParenClose);
                        return mk(ECast(e, null), t.pos);
                    }
                } else {
                    return mk(ECast(parsePostfix(), null), t.pos);
                }
            case TInt(v):
                next();
                return mk(EValue(v), t.pos);
            case TFloat(v):
                next();
                return mk(EValue(v), t.pos);
            case TString(v):
                next();
                return mk(EValue(v), t.pos);
            case TTrue:
                next();
                return mk(EValue(true), t.pos);
            case TFalse:
                next();
                return mk(EValue(false), t.pos);
            case TNull:
                next();
                return mk(EValue(null), t.pos);
            case TThis:
                next();
                return mk(EIdent("this"), t.pos);
            case TSuper:
                next();
                return mk(EIdent("super"), t.pos);
            case TNew:
                next();
                var type = parseType(false);
                var args = parseCallArgs();
                return mk(ENew(type, args), t.pos);
            case TIdent(v):
                next();
                // Check if it's an arrow function: arg -> body
                if (match(TArrow)) {
                    var body = parseExpr();
                    return mk(EFunction(null, [{ name: v, type: null }], null, body), t.pos);
                }
                return mk(EIdent(v), t.pos);
            case TParenOpen:
                next();
                // Check for lambda: (a, b) -> body or (a, b):Type -> body
                var checkpoint = pos;
                var lambdaArgs = [];
                var ok = true;
                if (!is(TParenClose)) {
                    if (isIdent(peek())) {
                        var name = expectIdent();
                        var type = parseOptType();
                        lambdaArgs.push({ name: name, type: type });
                        while (match(TComma)) {
                            if (isIdent(peek())) {
                                var argName = expectIdent();
                                var argType = parseOptType();
                                lambdaArgs.push({ name: argName, type: argType });
                            } else {
                                ok = false;
                                break;
                            }
                        }
                    } else {
                        ok = false;
                    }
                }
                if (ok && is(TParenClose)) {
                    next(); // consume TParenClose
                    var retType = parseOptType(false); // skip/parse return type annotation if present
                    if (is(TArrow)) {
                        expect(TArrow);
                        var body = parseExpr();
                        return mk(EFunction(null, lambdaArgs, retType, body), t.pos);
                    }
                }
                // Backtrack if not lambda
                pos = checkpoint;
                var e = parseExpr();
                expect(TParenClose);
                return e;
            case TFunction:
                next();
                var name = null;
                if (isIdent(peek())) {
                    name = expectIdent();
                }
                var args = parseArgs();
                var retType = parseOptType();
                var body = parseBlock();
                return mk(EFunction(name, args, retType, body), t.pos);
            case TBracketOpen:
                next();
                if (is(TBracketClose)) {
                    next();
                    return mk(EArrayDecl([]), t.pos);
                }
                var nextT = peek();
                if (nextT.def == TFor || nextT.def == TWhile || nextT.def == TIf) {
                    var compStmt = parseStatement();
                    expect(TBracketClose);
                    return desugarComprehension(compStmt, t.pos);
                }
                var first = parseExpr();
                switch (first.def) {
                    case EBinop("=>", key, value):
                        var pairs = [{ key: key, value: value }];
                        while (match(TComma)) {
                            var k = parseExpr();
                            switch (k.def) {
                                case EBinop("=>", nextKey, nextValue):
                                    pairs.push({ key: nextKey, value: nextValue });
                                default:
                                    throw new CompileException("Expected => in map declaration", k.pos.line, k.pos.col, file);
                            }
                        }
                        expect(TBracketClose);
                        return mk(EMapDecl(pairs), t.pos);
                    default:
                        var values = [first];
                        while (match(TComma)) {
                            values.push(parseExpr());
                        }
                        expect(TBracketClose);
                        return mk(EArrayDecl(values), t.pos);
                }
            case TBraceOpen:
                next();
                skipNewlines();
                // Check if it's object literal or block
                var checkpoint = pos;
                var isObj = false;
                if (isIdent(peek()) && tokens[pos+1].def == TColon) {
                    isObj = true;
                } else if (is(TBraceClose)) {
                    isObj = true;
                }
                pos = checkpoint;
                if (isObj) {
                    var fields = [];
                    if (!is(TBraceClose)) {
                        var fName = expectIdent();
                        expect(TColon);
                        var fExpr = parseExpr();
                        fields.push({ name: fName, expr: fExpr });
                        while (match(TComma)) {
                            skipNewlines();
                            if (is(TBraceClose)) break;
                            var name = expectIdent();
                            expect(TColon);
                            var expr = parseExpr();
                            fields.push({ name: name, expr: expr });
                        }
                    }
                    skipNewlines();
                    expect(TBraceClose);
                    return mk(EObjectDecl(fields), t.pos);
                } else {
                    // It's a block
                    pos = checkpoint;
                    var exprs = [];
                    while (!is(TBraceClose) && !is(TEof)) {
                        skipNewlines();
                        if (is(TBraceClose)) break;
                        exprs.push(parseStatement());
                        skipNewlines();
                    }
                    expect(TBraceClose);
                    return mk(EBlock(exprs), t.pos);
                }
            default:
                throw new CompileException('Unexpected token ${t.def}', t.pos.line, t.pos.col, file);
        }
    }

    // --- Parser Helpers ---

    function parseOptType(allowArrow:Bool = true):Null<TypeDecl> {
        if (match(TColon)) {
            return parseType(allowArrow);
        }
        return null;
    }

    public function parseType(allowArrow:Bool = true):TypeDecl {
        if (match(TBraceOpen)) {
            var fields = [];
            skipNewlines();
            if (!is(TBraceClose)) {
                match(TVar);
                var opt = match(TQuestion);
                var fName = expectIdent();
                expect(TColon);
                var fType = parseType(allowArrow);
                fields.push({ name: fName, type: fType, opt: opt });
                while (match(TComma) || match(TSemicolon)) {
                    skipNewlines();
                    if (is(TBraceClose)) break;
                    match(TVar);
                    var nextOpt = match(TQuestion);
                    var nextName = expectIdent();
                    expect(TColon);
                    var nextType = parseType(allowArrow);
                    fields.push({ name: nextName, type: nextType, opt: nextOpt });
                }
            }
            skipNewlines();
            expect(TBraceClose);
            var baseType = TAnonymous(fields);
            if (allowArrow && match(TArrow)) {
                var ret = parseType(allowArrow);
                return TFun([baseType], ret);
            }
            return baseType;
        }

        if (match(TParenOpen)) {
            var args = [];
            while (!is(TParenClose) && !is(TEof)) {
                args.push(parseType(allowArrow));
                if (match(TComma)) {}
            }
            expect(TParenClose);
            if (allowArrow && match(TArrow)) {
                var ret = parseType(allowArrow);
                return TFun(args, ret);
            }
            if (args.length == 1) return args[0];
            throw new CompileException("Invalid type parenthesization", peek().pos.line, peek().pos.col, file);
        }
        
        var path = [expectIdent()];
        while (match(TDot)) {
            path.push(expectIdent());
        }
        
        var params = [];
        if (match(TLess)) {
            params.push(parseType(allowArrow));
            while (match(TComma)) {
                params.push(parseType(allowArrow));
            }
            checkAndSplitShiftRight();
            expect(TGreater);
        }
        
        var baseType = TPath(path, params);
        
        if (allowArrow && match(TArrow)) {
            var ret = parseType(allowArrow);
            return TFun([baseType], ret);
        }
        
        return baseType;
    }

    inline function peek(offset:Int = 0):Token {
        if (pos + offset >= tokens.length) return tokens[tokens.length - 1];
        return tokens[pos + offset];
    }

    inline function next():Token {
        var t = tokens[pos];
        if (pos < tokens.length - 1) pos++;
        return t;
    }

    inline function is(def:TokenDef):Bool {
        return Type.enumIndex(peek().def) == Type.enumIndex(def);
    }

    inline function match(def:TokenDef):Bool {
        if (is(def)) {
            next();
            return true;
        }
        return false;
    }

    function expect(def:TokenDef):Token {
        var t = peek();
        if (is(def)) {
            next();
            return t;
        }
        throw new CompileException('Expected ${def} but got ${t.def}', t.pos.line, t.pos.col, file);
    }

    function isIdent(t:Token):Bool {
        return switch (t.def) {
            case TIdent(_): true;
            default: false;
        };
    }

    function expectIdent():String {
        var t = peek();
        return switch (t.def) {
            case TIdent(v):
                next();
                v;
            default:
                throw new CompileException('Expected identifier but got ${t.def}', t.pos.line, t.pos.col, file);
        };
    }

    function skipNewlines() {
        while (match(TNewline)) {}
    }

    inline function mk(def:ExprDef, pos:Pos):Expr {
        return { def: def, pos: pos };
    }

    function parseInterface(?meta:Array<{name:String, params:Array<Expr>}>):Expr {
        var t = expect(TInterface);
        var name = expectIdent();
        registerType(name, t.pos);
        var params = parseOptParams();
        var parents = [];
        if (match(TExtends)) {
            parents.push(parseType(false));
            while (match(TComma)) {
                parents.push(parseType(false));
            }
        }
        expect(TBraceOpen);
        skipNewlines();
        
        var fields = [];
        var methods = [];
        while (!is(TBraceClose) && !is(TEof)) {
            var fMeta = parseMetadata();
            // Interfaces are always public, but we allow modifiers to avoid parser syntax errors
            while (match(TPublic) || match(TPrivate) || match(TStatic) || match(TInline)) {}
            
            skipNewlines();
            var memberT = peek();
            if (memberT.def == TVar) {
                next();
                var fName = expectIdent();
                var prop = null;
                if (match(TParenOpen)) {
                    var getM = parsePropertyAccessor();
                    expect(TComma);
                    var setM = parsePropertyAccessor();
                    expect(TParenClose);
                    prop = { get: getM, set: setM };
                }
                var fType = parseOptType();
                expect(TSemicolon);
                fields.push({ name: fName, type: fType, property: prop, meta: fMeta });
            } else {
                expect(TFunction);
                var mName = expectIdent();
                var mArgs = parseArgs();
                var mRetType = parseOptType();
                var mBody = null;
                if (is(TBraceOpen)) {
                    mBody = parseStatement();
                } else {
                    expect(TSemicolon);
                }
                methods.push({ name: mName, args: mArgs, retType: mRetType, body: mBody, meta: fMeta });
            }
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EInterface(name, fields, methods, parents, params, meta), t.pos);
    }

    function parseEnum():Expr {
        var t = expect(TEnum);
        var name = expectIdent();
        registerType(name, t.pos);
        var params = parseOptParams();
        expect(TBraceOpen);
        skipNewlines();
        var constructors = [];
        while (!is(TBraceClose) && !is(TEof)) {
            var cName = expectIdent();
            var cArgs = null;
            if (match(TParenOpen)) {
                cArgs = [];
                if (!is(TParenClose)) {
                    var aName = expectIdent();
                    var aType = parseOptType();
                    cArgs.push({ name: aName, type: aType });
                    while (match(TComma)) {
                        var nextName = expectIdent();
                        var nextType = parseOptType();
                        cArgs.push({ name: nextName, type: nextType });
                    }
                }
                expect(TParenClose);
            }
            constructors.push({ name: cName, args: cArgs });
            expect(TSemicolon);
            skipNewlines();
        }
        expect(TBraceClose);
        return mk(EEnum(name, constructors, params), t.pos);
    }

    function parseTypedef():Expr {
        var t = expect(TTypedef);
        var name = expectIdent();
        registerType(name, t.pos);
        var params = parseOptParams();
        expect(TAssign);
        var type = parseType();
        match(TSemicolon);
        return mk(ETypedef(name, type, params), t.pos);
    }

    function isMapComprehension(expr:Expr):Bool {
        if (expr == null) return false;
        switch (expr.def) {
            case EBlock(exprs):
                if (exprs.length > 0) return isMapComprehension(exprs[exprs.length - 1]);
                return false;
            case EIf(_, e1, e2):
                return isMapComprehension(e1) || (e2 != null && isMapComprehension(e2));
            case EFor(_, _, body):
                return isMapComprehension(body);
            case EWhile(_, body):
                return isMapComprehension(body);
            case EDoWhile(_, body):
                return isMapComprehension(body);
            case ESwitch(_, cases, defExpr):
                for (c in cases) {
                    if (isMapComprehension(c.expr)) return true;
                }
                return defExpr != null && isMapComprehension(defExpr);
            case ETry(tryExpr, catches):
                if (isMapComprehension(tryExpr)) return true;
                for (c in catches) {
                    if (isMapComprehension(c.body)) return true;
                }
                return false;
            case EBinop("=>", _, _):
                return true;
            default:
                return false;
        }
    }

    function desugarComprehension(stmt:Expr, pos:Pos):Expr {
        var isMap = isMapComprehension(stmt);
        var compName = isMap ? "__comp_map_" + (compCounter++) : "__comp_arr_" + (compCounter++);
        var transformed = transformComprehension(stmt, compName, isMap);
        var initExpr = isMap ? mk(EMapDecl([]), pos) : mk(EArrayDecl([]), pos);
        var varDecl = mk(EVar(compName, null, initExpr), pos);
        var retExpr = mk(EIdent(compName), pos);
        return mk(EBlock([varDecl, transformed, retExpr]), pos);
    }

    function transformComprehension(expr:Expr, compName:String, isMap:Bool):Expr {
        if (expr == null) return null;
        var pos = expr.pos;
        switch (expr.def) {
            case EBlock(exprs):
                if (exprs.length > 0) {
                    var lastIdx = exprs.length - 1;
                    exprs[lastIdx] = transformComprehension(exprs[lastIdx], compName, isMap);
                }
                return expr;
            case EIf(cond, e1, e2):
                var newE1 = transformComprehension(e1, compName, isMap);
                var newE2 = e2 != null ? transformComprehension(e2, compName, isMap) : null;
                return mk(EIf(cond, newE1, newE2), pos);
            case EFor(v, it, body):
                var newBody = transformComprehension(body, compName, isMap);
                return mk(EFor(v, it, newBody), pos);
            case EWhile(cond, body):
                var newBody = transformComprehension(body, compName, isMap);
                return mk(EWhile(cond, newBody), pos);
            case EDoWhile(cond, body):
                var newBody = transformComprehension(body, compName, isMap);
                return mk(EDoWhile(cond, newBody), pos);
            case ESwitch(switchExpr, cases, defExpr):
                var newCases = [for (c in cases) { values: c.values, guard: c.guard, expr: transformComprehension(c.expr, compName, isMap) }];
                var newDefExpr = defExpr != null ? transformComprehension(defExpr, compName, isMap) : null;
                return mk(ESwitch(switchExpr, newCases, newDefExpr), pos);
            case ETry(tryExpr, catches):
                var newTryExpr = transformComprehension(tryExpr, compName, isMap);
                var newCatches = [for (c in catches) { pattern: c.pattern, type: c.type, guard: c.guard, body: transformComprehension(c.body, compName, isMap) }];
                return mk(ETry(newTryExpr, newCatches), pos);
            case EBreak, EContinue, EReturn(_), EThrow(_):
                return expr;
            default:
                if (isMap) {
                    switch (expr.def) {
                        case EBinop("=>", key, value):
                            var setField = mk(EField(mk(EIdent(compName), pos), "set"), pos);
                            return mk(ECall(setField, [key, value]), pos);
                        default:
                            throw new CompileException("Map comprehension expected key => value expression", pos.line, pos.col, file);
                    }
                } else {
                    var pushField = mk(EField(mk(EIdent(compName), pos), "push"), pos);
                    return mk(ECall(pushField, [expr]), pos);
                }
        }
    }

    function typeToString(type:TypeDecl):String {
        return switch (type) {
            case TPath(path, params):
                var base = path.join(".");
                if (params != null && params.length > 0) {
                    base + "<" + params.map(typeToString).join(", ") + ">";
                } else {
                    base;
                }
            case TFun(args, ret):
                var argsStr = args.map(typeToString).join(", ");
                "(" + argsStr + ") -> " + typeToString(ret);
            case TAnonymous(fields):
                var fieldsStr = fields.map(f -> (f.opt == true ? "?" : "") + f.name + ":" + typeToString(f.type)).join(", ");
                "{" + fieldsStr + "}";
        }
    }
}
