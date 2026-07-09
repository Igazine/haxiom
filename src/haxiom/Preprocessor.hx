package haxiom;

import haxiom.AST;

class Preprocessor {
    public static function evaluate(exprStr:String, flags:Map<String, Bool>):Bool {
        if (exprStr == null || StringTools.trim(exprStr) == "") return true;
        try {
            var lexer = new Lexer(exprStr, "preprocessor", flags);
            var tokens = lexer.tokenize();
            var parser = new Parser(tokens, "preprocessor");
            var ast = parser.parseExprOnly();
            return evalExpr(ast, flags);
        } catch (e:Dynamic) {
            throw 'Preprocessor error parsing "$exprStr": ' + Std.string(e);
        }
        return false;
    }

    static function evalExpr(e:Expr, flags:Map<String, Bool>):Dynamic {
        switch (e.def) {
            case EIdent(name):
                return flags.get(name) == true;
            case EValue(v):
                return v;
            case EUnop("!", sub):
                return !evalExpr(sub, flags);
            case EBinop("&&", e1, e2):
                return evalExpr(e1, flags) && evalExpr(e2, flags);
            case EBinop("||", e1, e2):
                return evalExpr(e1, flags) || evalExpr(e2, flags);
            case EBinop("==", e1, e2):
                return evalExpr(e1, flags) == evalExpr(e2, flags);
            case EBinop("!=", e1, e2):
                return evalExpr(e1, flags) != evalExpr(e2, flags);
            case EBinop("<", e1, e2):
                return evalExpr(e1, flags) < evalExpr(e2, flags);
            case EBinop("<=", e1, e2):
                return evalExpr(e1, flags) <= evalExpr(e2, flags);
            case EBinop(">", e1, e2):
                return evalExpr(e1, flags) > evalExpr(e2, flags);
            case EBinop(">=", e1, e2):
                return evalExpr(e1, flags) >= evalExpr(e2, flags);
            case EBlock(exprs):
                if (exprs.length == 1) return evalExpr(exprs[0], flags);
                throw "Preprocessor expression cannot contain blocks";
            default:
                throw 'Unsupported preprocessor expression: ' + Std.string(e.def);
        }
        return false;
    }
}
