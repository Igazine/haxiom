package haxiom;

import haxiom.AST;

@:allow(haxiom)
class Preprocessor {
	static function getExprPath(e:Expr):Array<String> {
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
			case ESafeField(objExpr, field):
				var sub = getExprPath(objExpr);
				if (sub != null) {
					return sub.concat([field]);
				}
			default:
		}
		return null;
	}

	static function validatePreprocessExpr(e:Expr) {
		if (e == null)
			return;

		var path = getExprPath(e);
		if (path != null) {
			var fullPath = path.join(".");
			if (fullPath != "haxiom_script" && fullPath != "haxiom.script") {
				throw 'Only the "haxiom_script" and "haxiom.script" preprocessor conditionals are allowed. Found: "$fullPath"';
			}
			return;
		}

		switch (e.def) {
			case EUnop(_, sub):
				validatePreprocessExpr(sub);
			case EBinop(_, e1, e2):
				validatePreprocessExpr(e1);
				validatePreprocessExpr(e2);
			case EBlock(exprs):
				for (expr in exprs) {
					validatePreprocessExpr(expr);
				}
			default:
				// values (like true/false) are fine
		}
	}

	static function evaluate(exprStr:String, flags:Map<String, Bool>):Bool {
		if (exprStr == null || StringTools.trim(exprStr) == "")
			return true;
		try {
			var lexer = new Lexer(exprStr, "preprocessor", flags);
			var tokens = lexer.tokenize();
			var parser = new Parser(tokens, "preprocessor");
			var ast = parser.parseExprOnly();
			validatePreprocessExpr(ast);
			return evalExpr(ast, flags);
		} catch (e:Dynamic) {
			throw 'Preprocessor error parsing "$exprStr": ' + Std.string(e);
		}
		return false;
	}

	static function evalExpr(e:Expr, flags:Map<String, Bool>):Dynamic {
		switch (e.def) {
			case EIdent(name):
				if (name == "haxiom_script") {
					return flags.get("haxiom_script") == true;
				}
				return flags.get(name) == true;
			case EField(obj, field):
				var path = getExprPath(e);
				if (path != null) {
					var fullPath = path.join(".");
					if (fullPath == "haxiom.script") {
						return flags.get("haxiom_script") == true || flags.get("haxiom.script") == true;
					}
				}
				throw 'Unsupported preprocessor expression: ' + Std.string(e.def);
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
				if (exprs.length == 1)
					return evalExpr(exprs[0], flags);
				throw "Preprocessor expression cannot contain blocks";
			default:
				throw 'Unsupported preprocessor expression: ' + Std.string(e.def);
		}
		return false;
	}
}
