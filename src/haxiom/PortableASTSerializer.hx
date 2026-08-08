package haxiom;

import haxe.Json;
import haxe.io.Bytes;
import haxiom.AST;

@:allow(haxiom)
class PortableASTSerializer {
	static function serializeToBytes(expr:Expr):Bytes {
		return Bytes.ofString(Json.stringify(exprToData(expr)));
	}

	static function deserializeFromBytes(bytes:Bytes, ?maxBytes:Int = 64 * 1024 * 1024, ?maxDepth:Int = 512):Expr {
		if (bytes == null)
			throw "Invalid portable AST: data is null";
		if (maxBytes > 0 && bytes.length > maxBytes)
			throw 'Invalid portable AST: payload exceeds limit (${bytes.length} > $maxBytes bytes)';

		var json = bytes.toString();
		validateJsonDepth(json, maxDepth);
		var data:Dynamic = Json.parse(json);
		if (data == null || !Reflect.isObject(data) || !Reflect.hasField(data, "tag"))
			throw "Invalid portable AST: root expression is missing its tag";
		return dataToExpr(data);
	}

	static function validateJsonDepth(json:String, maxDepth:Int):Void {
		if (maxDepth <= 0)
			return;
		var depth = 0;
		var inString = false;
		var escaped = false;
		for (i in 0...json.length) {
			var c = json.charCodeAt(i);
			if (inString) {
				if (escaped) {
					escaped = false;
				} else if (c == 92) {
					escaped = true;
				} else if (c == 34) {
					inString = false;
				}
				continue;
			}
			if (c == 34) {
				inString = true;
			} else if (c == 123 || c == 91) {
				depth++;
				if (depth > maxDepth)
					throw 'Invalid portable AST: JSON nesting exceeds limit ($maxDepth)';
			} else if (c == 125 || c == 93) {
				depth--;
				if (depth < 0)
					throw "Invalid portable AST: unbalanced JSON structure";
			}
		}
	}

	static function posToData(pos:Pos):Dynamic {
		if (pos == null)
			return null;
		var data:Dynamic = {line: pos.line, col: pos.col};
		if (pos.file != null)
			Reflect.setField(data, "file", pos.file);
		return data;
	}

	static function dataToPos(data:Dynamic):Pos {
		if (data == null)
			return null;
		var pos:Pos = {
			line: Reflect.field(data, "line"),
			col: Reflect.field(data, "col")
		};
		if (Reflect.hasField(data, "file"))
			pos.file = Reflect.field(data, "file");
		return pos;
	}

	static function valueToData(v:Dynamic):Dynamic {
		if (v == null)
			return {k: "null"};
		if (Std.isOfType(v, Bytes)) {
			var bytes:Bytes = cast v;
			return {k: "bytes", hex: bytes.toHex()};
		}
		if (Std.isOfType(v, BinaryResourceRefHolder) || Reflect.hasField(v, "key")) {
			return {k: "resourceRef", key: Std.string(Reflect.field(v, "key"))};
		}
		return switch (Type.typeof(v)) {
			case TBool:
				{k: "bool", v: v};
			case TInt:
				{k: "int", v: v};
			case TFloat:
				{k: "float", v: v};
			case TClass(c) if (c == String || Type.getClassName(c) == "String"):
				{k: "string", v: Std.string(v)};
			default:
				throw "Unsupported AST literal value for portable serialization: " + Std.string(v);
		}
	}

	static function dataToValue(data:Dynamic):Dynamic {
		return switch ((Reflect.field(data, "k") : String)) {
			case "null": null;
			case "bool": Reflect.field(data, "v") == true;
			case "int": Std.int(Reflect.field(data, "v"));
			case "float": (Reflect.field(data, "v") : Float);
			case "string": Std.string(Reflect.field(data, "v"));
			case "bytes": Bytes.ofHex(Std.string(Reflect.field(data, "hex")));
			case "resourceRef": new BinaryResourceRefHolder(Std.string(Reflect.field(data, "key")));
			case other: throw "Unknown portable AST literal tag: " + other;
		}
	}

	static function exprArrayToData(values:Array<Expr>):Array<Dynamic> {
		return values == null ? null : [for (v in values) exprToData(v)];
	}

	static function dataToExprArray(values:Array<Dynamic>):Array<Expr> {
		return values == null ? null : [for (v in values) dataToExpr(v)];
	}

	static function typeToData(t:TypeDecl):Dynamic {
		if (t == null)
			return null;
		return switch (t) {
			case TPath(path, params):
				{tag: "TPath", path: path, params: [for (p in params) typeToData(p)]};
			case TFun(args, ret):
				{tag: "TFun", args: [for (a in args) typeToData(a)], ret: typeToData(ret)};
			case TAnonymous(fields, extendsTypes):
				{
					tag: "TAnonymous",
					fields: [
						for (f in fields)
							{name: f.name, type: typeToData(f.type), opt: f.opt == true}
					],
					extendsTypes: extendsTypes == null ? null : [for (e in extendsTypes) typeToData(e)]
				};
		}
	}

	static function dataToType(data:Dynamic):TypeDecl {
		if (data == null)
			return null;
		return switch ((Reflect.field(data, "tag") : String)) {
			case "TPath":
				TPath(cast Reflect.field(data, "path"), [for (p in (Reflect.field(data, "params") : Array<Dynamic>)) dataToType(p)]);
			case "TFun":
				TFun([for (a in (Reflect.field(data, "args") : Array<Dynamic>)) dataToType(a)], dataToType(Reflect.field(data, "ret")));
			case "TAnonymous":
				var extData:Array<Dynamic> = Reflect.field(data, "extendsTypes");
				TAnonymous([
					for (f in (Reflect.field(data, "fields") : Array<Dynamic>))
						{name: Std.string(Reflect.field(f, "name")), type: dataToType(Reflect.field(f, "type")), opt: Reflect.field(f, "opt") == true}
				], extData == null ? null : [for (e in extData) dataToType(e)]);
			case other:
				throw "Unknown portable AST type tag: " + other;
		}
	}

	static function argsToData(args:Array<FunctionArg>):Array<Dynamic> {
		return args == null ? null : [
			for (a in args)
				{name: a.name, type: typeToData(a.type), isRest: a.isRest == true}
		];
	}

	static function dataToArgs(args:Array<Dynamic>):Array<FunctionArg> {
		return args == null ? null : [
			for (a in args)
				{name: Std.string(Reflect.field(a, "name")), type: dataToType(Reflect.field(a, "type")), isRest: Reflect.field(a, "isRest") == true}
		];
	}

	static function paramsToData(params:Array<TypeParamDef>):Array<Dynamic> {
		return params == null ? null : [
			for (p in params)
				{name: p.name, constraint: typeToData(p.constraint)}
		];
	}

	static function dataToParams(params:Array<Dynamic>):Array<TypeParamDef> {
		return params == null ? null : [
			for (p in params)
				{name: Std.string(Reflect.field(p, "name")), constraint: dataToType(Reflect.field(p, "constraint"))}
		];
	}

	static function metaToData(meta:Array<{name:String, params:Array<Expr>}>):Array<Dynamic> {
		return meta == null ? null : [
			for (m in meta)
				{name: m.name, params: exprArrayToData(m.params)}
		];
	}

	static function dataToMeta(meta:Array<Dynamic>):Array<{name:String, params:Array<Expr>}> {
		return meta == null ? null : [
			for (m in meta)
				{name: Std.string(Reflect.field(m, "name")), params: dataToExprArray(Reflect.field(m, "params"))}
		];
	}

	static function propToData(prop:{get:String, set:String}):Dynamic {
		return prop == null ? null : {get: prop.get, set: prop.set};
	}

	static function dataToProp(prop:Dynamic):{get:String, set:String} {
		return prop == null ? null : {get: Std.string(Reflect.field(prop, "get")), set: Std.string(Reflect.field(prop, "set"))};
	}

	static function exprToData(expr:Expr):Dynamic {
		if (expr == null)
			return null;
		var data:Dynamic = {pos: posToData(expr.pos)};
		switch (expr.def) {
			case EValue(v):
				Reflect.setField(data, "tag", "EValue");
				Reflect.setField(data, "value", valueToData(v));
			case EIdent(v):
				Reflect.setField(data, "tag", "EIdent");
				Reflect.setField(data, "value", v);
			case EEReg(pattern, flags):
				Reflect.setField(data, "tag", "EEReg");
				Reflect.setField(data, "pattern", pattern);
				Reflect.setField(data, "flags", flags);
			case EVar(name, type, e, isFinal, meta):
				Reflect.setField(data, "tag", "EVar");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "type", typeToData(type));
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "isFinal", isFinal == true);
				Reflect.setField(data, "meta", metaToData(meta));
			case EAssign(target, e):
				Reflect.setField(data, "tag", "EAssign");
				Reflect.setField(data, "target", exprToData(target));
				Reflect.setField(data, "expr", exprToData(e));
			case EBinop(op, e1, e2):
				Reflect.setField(data, "tag", "EBinop");
				Reflect.setField(data, "op", op);
				Reflect.setField(data, "e1", exprToData(e1));
				Reflect.setField(data, "e2", exprToData(e2));
			case EUnop(op, e):
				Reflect.setField(data, "tag", "EUnop");
				Reflect.setField(data, "op", op);
				Reflect.setField(data, "expr", exprToData(e));
			case EField(e, field):
				Reflect.setField(data, "tag", "EField");
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "field", field);
			case ECall(e, args):
				Reflect.setField(data, "tag", "ECall");
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "args", exprArrayToData(args));
			case EArrayDecl(values):
				Reflect.setField(data, "tag", "EArrayDecl");
				Reflect.setField(data, "values", exprArrayToData(values));
			case EObjectDecl(fields):
				Reflect.setField(data, "tag", "EObjectDecl");
				Reflect.setField(data, "fields", [for (f in fields) {name: f.name, expr: exprToData(f.expr)}]);
			case EMapDecl(values):
				Reflect.setField(data, "tag", "EMapDecl");
				Reflect.setField(data, "values", [for (v in values) {key: exprToData(v.key), value: exprToData(v.value)}]);
			case EClass(name, fields, methods, parent, interfaces, params, meta, isExtern):
				Reflect.setField(data, "tag", "EClass");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "fields", [
					for (f in fields)
						{
							name: f.name,
							type: typeToData(f.type),
							expr: exprToData(f.expr),
							isStatic: f.isStatic,
							isPublic: f.isPublic,
							isFinal: f.isFinal,
							property: propToData(f.property),
							meta: metaToData(f.meta),
							isExtern: f.isExtern == true
						}
				]);
				Reflect.setField(data, "methods", [
					for (m in methods)
						{
							name: m.name,
							args: argsToData(m.args),
							retType: typeToData(m.retType),
							body: exprToData(m.body),
							isStatic: m.isStatic,
							isPublic: m.isPublic,
							isOverride: m.isOverride == true,
							isAbstract: m.isAbstract == true,
							params: paramsToData(m.params),
							meta: metaToData(m.meta),
							isExtern: m.isExtern == true
						}
				]);
				Reflect.setField(data, "parent", typeToData(parent));
				Reflect.setField(data, "interfaces", interfaces == null ? null : [for (i in interfaces) typeToData(i)]);
				Reflect.setField(data, "params", paramsToData(params));
				Reflect.setField(data, "meta", metaToData(meta));
				Reflect.setField(data, "isExtern", isExtern == true);
			case EBlock(exprs):
				Reflect.setField(data, "tag", "EBlock");
				Reflect.setField(data, "exprs", exprArrayToData(exprs));
			case EFunction(name, args, retType, body, params):
				Reflect.setField(data, "tag", "EFunction");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "args", argsToData(args));
				Reflect.setField(data, "retType", typeToData(retType));
				Reflect.setField(data, "body", exprToData(body));
				Reflect.setField(data, "params", paramsToData(params));
			case EIf(cond, e1, e2):
				Reflect.setField(data, "tag", "EIf");
				Reflect.setField(data, "cond", exprToData(cond));
				Reflect.setField(data, "e1", exprToData(e1));
				Reflect.setField(data, "e2", exprToData(e2));
			case EWhile(cond, e):
				Reflect.setField(data, "tag", "EWhile");
				Reflect.setField(data, "cond", exprToData(cond));
				Reflect.setField(data, "expr", exprToData(e));
			case EDoWhile(cond, e):
				Reflect.setField(data, "tag", "EDoWhile");
				Reflect.setField(data, "cond", exprToData(cond));
				Reflect.setField(data, "expr", exprToData(e));
			case EFor(v, it, e):
				Reflect.setField(data, "tag", "EFor");
				Reflect.setField(data, "name", v);
				Reflect.setField(data, "iter", exprToData(it));
				Reflect.setField(data, "expr", exprToData(e));
			case ESwitch(e, cases, defExpr):
				Reflect.setField(data, "tag", "ESwitch");
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "cases", [for (c in cases) {values: exprArrayToData(c.values), guard: exprToData(c.guard), expr: exprToData(c.expr)}]);
				Reflect.setField(data, "defExpr", exprToData(defExpr));
			case EReturn(e):
				Reflect.setField(data, "tag", "EReturn");
				Reflect.setField(data, "expr", exprToData(e));
			case EBreak:
				Reflect.setField(data, "tag", "EBreak");
			case EContinue:
				Reflect.setField(data, "tag", "EContinue");
			case EPackage(path):
				Reflect.setField(data, "tag", "EPackage");
				Reflect.setField(data, "path", path);
			case EImport(path, alias):
				Reflect.setField(data, "tag", "EImport");
				Reflect.setField(data, "path", path);
				Reflect.setField(data, "alias", alias);
			case EUsing(path):
				Reflect.setField(data, "tag", "EUsing");
				Reflect.setField(data, "path", path);
			case EThrow(e):
				Reflect.setField(data, "tag", "EThrow");
				Reflect.setField(data, "expr", exprToData(e));
			case ETry(tryExpr, catches):
				Reflect.setField(data, "tag", "ETry");
				Reflect.setField(data, "tryExpr", exprToData(tryExpr));
				Reflect.setField(data, "catches", [
					for (c in catches)
						{pattern: exprToData(c.pattern), type: typeToData(c.type), guard: exprToData(c.guard), body: exprToData(c.body)}
				]);
			case ECast(e, type):
				Reflect.setField(data, "tag", "ECast");
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "type", typeToData(type));
			case EInterface(name, fields, methods, parents, params, meta):
				Reflect.setField(data, "tag", "EInterface");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "fields", [
					for (f in fields)
						{name: f.name, type: typeToData(f.type), property: propToData(f.property), meta: metaToData(f.meta)}
				]);
				Reflect.setField(data, "methods", [
					for (m in methods)
						{name: m.name, args: argsToData(m.args), retType: typeToData(m.retType), body: exprToData(m.body), params: paramsToData(m.params), meta: metaToData(m.meta)}
				]);
				Reflect.setField(data, "parents", parents == null ? null : [for (p in parents) typeToData(p)]);
				Reflect.setField(data, "params", paramsToData(params));
				Reflect.setField(data, "meta", metaToData(meta));
			case EEnum(name, constructors, params):
				Reflect.setField(data, "tag", "EEnum");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "constructors", [for (c in constructors) {name: c.name, args: argsToData(c.args)}]);
				Reflect.setField(data, "params", paramsToData(params));
			case ESafeField(e, field):
				Reflect.setField(data, "tag", "ESafeField");
				Reflect.setField(data, "expr", exprToData(e));
				Reflect.setField(data, "field", field);
			case ENew(type, args):
				Reflect.setField(data, "tag", "ENew");
				Reflect.setField(data, "type", typeToData(type));
				Reflect.setField(data, "args", exprArrayToData(args));
			case EAbstract(name, underlyingType, fields, methods, params, meta):
				Reflect.setField(data, "tag", "EAbstract");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "underlyingType", typeToData(underlyingType));
				Reflect.setField(data, "fields", [
					for (f in fields)
						{name: f.name, type: typeToData(f.type), expr: exprToData(f.expr), isStatic: f.isStatic, isPublic: f.isPublic, isFinal: f.isFinal, property: propToData(f.property), meta: metaToData(f.meta)}
				]);
				Reflect.setField(data, "methods", [
					for (m in methods)
						{name: m.name, args: argsToData(m.args), retType: typeToData(m.retType), body: exprToData(m.body), isStatic: m.isStatic, isPublic: m.isPublic, params: paramsToData(m.params), meta: metaToData(m.meta)}
				]);
				Reflect.setField(data, "params", paramsToData(params));
				Reflect.setField(data, "meta", metaToData(meta));
			case ETypedef(name, type, params):
				Reflect.setField(data, "tag", "ETypedef");
				Reflect.setField(data, "name", name);
				Reflect.setField(data, "type", typeToData(type));
				Reflect.setField(data, "params", paramsToData(params));
			case EMeta(meta, e):
				Reflect.setField(data, "tag", "EMeta");
				Reflect.setField(data, "meta", metaToData(meta));
				Reflect.setField(data, "expr", exprToData(e));
		}
		return data;
	}

	static function dataToExpr(data:Dynamic):Expr {
		if (data == null)
			return null;
		var pos = dataToPos(Reflect.field(data, "pos"));
		var tag:String = Reflect.field(data, "tag");
		var def:ExprDef = switch (tag) {
			case "EValue": EValue(dataToValue(Reflect.field(data, "value")));
			case "EIdent": EIdent(Std.string(Reflect.field(data, "value")));
			case "EEReg": EEReg(Std.string(Reflect.field(data, "pattern")), Std.string(Reflect.field(data, "flags")));
			case "EVar": EVar(Std.string(Reflect.field(data, "name")), dataToType(Reflect.field(data, "type")), dataToExpr(Reflect.field(data, "expr")), Reflect.field(data, "isFinal") == true, dataToMeta(Reflect.field(data, "meta")));
			case "EAssign": EAssign(dataToExpr(Reflect.field(data, "target")), dataToExpr(Reflect.field(data, "expr")));
			case "EBinop": EBinop(Std.string(Reflect.field(data, "op")), dataToExpr(Reflect.field(data, "e1")), dataToExpr(Reflect.field(data, "e2")));
			case "EUnop": EUnop(Std.string(Reflect.field(data, "op")), dataToExpr(Reflect.field(data, "expr")));
			case "EField": EField(dataToExpr(Reflect.field(data, "expr")), Std.string(Reflect.field(data, "field")));
			case "ECall": ECall(dataToExpr(Reflect.field(data, "expr")), dataToExprArray(Reflect.field(data, "args")));
			case "EArrayDecl": EArrayDecl(dataToExprArray(Reflect.field(data, "values")));
			case "EObjectDecl":
				EObjectDecl([for (f in (Reflect.field(data, "fields") : Array<Dynamic>)) {name: Std.string(Reflect.field(f, "name")), expr: dataToExpr(Reflect.field(f, "expr"))}]);
			case "EMapDecl":
				EMapDecl([for (v in (Reflect.field(data, "values") : Array<Dynamic>)) {key: dataToExpr(Reflect.field(v, "key")), value: dataToExpr(Reflect.field(v, "value"))}]);
			case "EClass":
				var interfacesData:Array<Dynamic> = Reflect.field(data, "interfaces");
				EClass(Std.string(Reflect.field(data, "name")), [
					for (f in (Reflect.field(data, "fields") : Array<Dynamic>))
						{
							name: Std.string(Reflect.field(f, "name")),
							type: dataToType(Reflect.field(f, "type")),
							expr: dataToExpr(Reflect.field(f, "expr")),
							isStatic: Reflect.field(f, "isStatic") == true,
							isPublic: Reflect.field(f, "isPublic") == true,
							isFinal: Reflect.field(f, "isFinal") == true,
							property: dataToProp(Reflect.field(f, "property")),
							meta: dataToMeta(Reflect.field(f, "meta")),
							isExtern: Reflect.field(f, "isExtern") == true
						}
				], [
					for (m in (Reflect.field(data, "methods") : Array<Dynamic>))
						{
							name: Std.string(Reflect.field(m, "name")),
							args: dataToArgs(Reflect.field(m, "args")),
							retType: dataToType(Reflect.field(m, "retType")),
							body: dataToExpr(Reflect.field(m, "body")),
							isStatic: Reflect.field(m, "isStatic") == true,
							isPublic: Reflect.field(m, "isPublic") == true,
							isOverride: Reflect.field(m, "isOverride") == true,
							isAbstract: Reflect.field(m, "isAbstract") == true,
							params: dataToParams(Reflect.field(m, "params")),
							meta: dataToMeta(Reflect.field(m, "meta")),
							isExtern: Reflect.field(m, "isExtern") == true
						}
				], dataToType(Reflect.field(data, "parent")), interfacesData == null ? null : [for (i in interfacesData) dataToType(i)], dataToParams(Reflect.field(data, "params")), dataToMeta(Reflect.field(data, "meta")), Reflect.field(data, "isExtern") == true);
			case "EBlock": EBlock(dataToExprArray(Reflect.field(data, "exprs")));
			case "EFunction": EFunction(Reflect.field(data, "name"), dataToArgs(Reflect.field(data, "args")), dataToType(Reflect.field(data, "retType")), dataToExpr(Reflect.field(data, "body")), dataToParams(Reflect.field(data, "params")));
			case "EIf": EIf(dataToExpr(Reflect.field(data, "cond")), dataToExpr(Reflect.field(data, "e1")), dataToExpr(Reflect.field(data, "e2")));
			case "EWhile": EWhile(dataToExpr(Reflect.field(data, "cond")), dataToExpr(Reflect.field(data, "expr")));
			case "EDoWhile": EDoWhile(dataToExpr(Reflect.field(data, "cond")), dataToExpr(Reflect.field(data, "expr")));
			case "EFor": EFor(Std.string(Reflect.field(data, "name")), dataToExpr(Reflect.field(data, "iter")), dataToExpr(Reflect.field(data, "expr")));
			case "ESwitch":
				ESwitch(dataToExpr(Reflect.field(data, "expr")), [
					for (c in (Reflect.field(data, "cases") : Array<Dynamic>))
						{values: dataToExprArray(Reflect.field(c, "values")), guard: dataToExpr(Reflect.field(c, "guard")), expr: dataToExpr(Reflect.field(c, "expr"))}
				], dataToExpr(Reflect.field(data, "defExpr")));
			case "EReturn": EReturn(dataToExpr(Reflect.field(data, "expr")));
			case "EBreak": EBreak;
			case "EContinue": EContinue;
			case "EPackage": EPackage(cast Reflect.field(data, "path"));
			case "EImport": EImport(cast Reflect.field(data, "path"), Reflect.field(data, "alias"));
			case "EUsing": EUsing(cast Reflect.field(data, "path"));
			case "EThrow": EThrow(dataToExpr(Reflect.field(data, "expr")));
			case "ETry":
				ETry(dataToExpr(Reflect.field(data, "tryExpr")), [
					for (c in (Reflect.field(data, "catches") : Array<Dynamic>))
						{pattern: dataToExpr(Reflect.field(c, "pattern")), type: dataToType(Reflect.field(c, "type")), guard: dataToExpr(Reflect.field(c, "guard")), body: dataToExpr(Reflect.field(c, "body"))}
				]);
			case "ECast": ECast(dataToExpr(Reflect.field(data, "expr")), dataToType(Reflect.field(data, "type")));
			case "EInterface":
				var parentsData:Array<Dynamic> = Reflect.field(data, "parents");
				EInterface(Std.string(Reflect.field(data, "name")), [
					for (f in (Reflect.field(data, "fields") : Array<Dynamic>))
						{name: Std.string(Reflect.field(f, "name")), type: dataToType(Reflect.field(f, "type")), property: dataToProp(Reflect.field(f, "property")), meta: dataToMeta(Reflect.field(f, "meta"))}
				], [
					for (m in (Reflect.field(data, "methods") : Array<Dynamic>))
						{name: Std.string(Reflect.field(m, "name")), args: dataToArgs(Reflect.field(m, "args")), retType: dataToType(Reflect.field(m, "retType")), body: dataToExpr(Reflect.field(m, "body")), params: dataToParams(Reflect.field(m, "params")), meta: dataToMeta(Reflect.field(m, "meta"))}
				], parentsData == null ? null : [for (p in parentsData) dataToType(p)], dataToParams(Reflect.field(data, "params")), dataToMeta(Reflect.field(data, "meta")));
			case "EEnum":
				EEnum(Std.string(Reflect.field(data, "name")), [
					for (c in (Reflect.field(data, "constructors") : Array<Dynamic>))
						{name: Std.string(Reflect.field(c, "name")), args: dataToArgs(Reflect.field(c, "args"))}
				], dataToParams(Reflect.field(data, "params")));
			case "ESafeField": ESafeField(dataToExpr(Reflect.field(data, "expr")), Std.string(Reflect.field(data, "field")));
			case "ENew": ENew(dataToType(Reflect.field(data, "type")), dataToExprArray(Reflect.field(data, "args")));
			case "EAbstract":
				EAbstract(Std.string(Reflect.field(data, "name")), dataToType(Reflect.field(data, "underlyingType")), [
					for (f in (Reflect.field(data, "fields") : Array<Dynamic>))
						{name: Std.string(Reflect.field(f, "name")), type: dataToType(Reflect.field(f, "type")), expr: dataToExpr(Reflect.field(f, "expr")), isStatic: Reflect.field(f, "isStatic") == true, isPublic: Reflect.field(f, "isPublic") == true, isFinal: Reflect.field(f, "isFinal") == true, property: dataToProp(Reflect.field(f, "property")), meta: dataToMeta(Reflect.field(f, "meta"))}
				], [
					for (m in (Reflect.field(data, "methods") : Array<Dynamic>))
						{name: Std.string(Reflect.field(m, "name")), args: dataToArgs(Reflect.field(m, "args")), retType: dataToType(Reflect.field(m, "retType")), body: dataToExpr(Reflect.field(m, "body")), isStatic: Reflect.field(m, "isStatic") == true, isPublic: Reflect.field(m, "isPublic") == true, params: dataToParams(Reflect.field(m, "params")), meta: dataToMeta(Reflect.field(m, "meta"))}
				], dataToParams(Reflect.field(data, "params")), dataToMeta(Reflect.field(data, "meta")));
			case "ETypedef": ETypedef(Std.string(Reflect.field(data, "name")), dataToType(Reflect.field(data, "type")), dataToParams(Reflect.field(data, "params")));
			case "EMeta": EMeta(dataToMeta(Reflect.field(data, "meta")), dataToExpr(Reflect.field(data, "expr")));
			case other: throw "Unknown portable AST expr tag: " + other;
		}
		return {def: def, pos: pos};
	}
}
