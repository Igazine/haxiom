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

	static function isValidIdentifierPath(pathStr:String):Bool {
		if (pathStr == null || pathStr.length == 0)
			return false;
		var parts = pathStr.split(".");
		for (part in parts) {
			if (part.length == 0)
				return false;
			var firstChar = StringTools.fastCodeAt(part, 0);
			var isFirstValid = (firstChar >= 'a'.code && firstChar <= 'z'.code)
				|| (firstChar >= 'A'.code && firstChar <= 'Z'.code)
				|| firstChar == '_'.code;
			if (!isFirstValid)
				return false;
			for (i in 1...part.length) {
				var c = StringTools.fastCodeAt(part, i);
				var isValidChar = (c >= 'a'.code && c <= 'z'.code)
					|| (c >= 'A'.code && c <= 'Z'.code)
					|| (c >= '0'.code && c <= '9'.code)
					|| c == '_'.code;
				if (!isValidChar)
					return false;
			}
		}
		return true;
	}

	static function validatePreprocessExpr(e:Expr) {
		if (e == null)
			return;

		var path = getExprPath(e);
		if (path != null) {
			var fullPath = path.join(".");
			if (!isValidIdentifierPath(fullPath)) {
				throw 'Invalid preprocessor flag identifier syntax: "$fullPath"';
			}
			return;
		}

		switch (e.def) {
			case EValue(v):
				if (Std.isOfType(v, Bool)) {
					return;
				}
				throw 'Invalid preprocessor flag identifier syntax: "$v"';
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
				throw 'Invalid preprocessor expression: ' + Std.string(e.def);
		}
	}

	static function evaluate(exprStr:String, flags:Map<String, Bool>):Bool {
		if (exprStr == null || PortableStringTools.trim(exprStr) == "")
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
				return flags != null && flags.get(name) == true;
			case EField(obj, field):
				var path = getExprPath(e);
				if (path != null) {
					var fullPath = path.join(".");
					if (flags != null && flags.exists(fullPath)) {
						return flags.get(fullPath) == true;
					}
					var lastPart = path[path.length - 1];
					return flags != null && flags.get(lastPart) == true;
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
