package haxiom;

import haxiom.AST;

/** Enforces Haxe static-context rules before a field initializer can execute. */
@:allow(haxiom)
class StaticInitializerValidator {
	static function validate(expr:Expr):Void {
		if (expr == null)
			return;
		switch (expr.def) {
			case EBlock(exprs):
				for (child in exprs)
					validate(child);
			case EClass(name, fields, methods, _, _, _, _, isExtern):
				if (isExtern != true)
					validateType(name, cast fields, cast methods);
			case EAbstract(name, _, fields, methods, _, _):
				validateType(name, cast fields, cast methods);
			default:
		}
	}

	static function validateType(name:String, fields:Array<Dynamic>, methods:Array<Dynamic>):Void {
		var members:Map<String, Bool> = new Map();
		for (field in fields)
			members.set(field.name, field.isStatic);
		for (method in methods)
			members.set(method.name, method.isStatic);

		for (field in fields) {
			if (field.isStatic && field.expr != null)
				validateExpr(field.expr, name, members, new Map(), 0, 0);
		}
	}

	static function validateExpr(expr:Expr, typeName:String, members:Map<String, Bool>, locals:Map<String, Bool>, functionDepth:Int,
			loopDepth:Int):Void {
		if (expr == null)
			return;

		switch (expr.def) {
			case EValue(_) | EEReg(_, _):
			case EIdent(name):
				if (name == "this" || name == "super")
					fail('Cannot use \'$name\' in a static field initializer', expr.pos);
				if (!locals.exists(name) && members.exists(name) && members.get(name) != true)
					fail('Cannot access instance member $name from static field initializer of $typeName', expr.pos);
			case EVar(name, _, init, _, _):
				validateExpr(init, typeName, members, locals, functionDepth, loopDepth);
				locals.set(name, true);
			case EAssign(target, value):
				validateExpr(target, typeName, members, locals, functionDepth, loopDepth);
				validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
			case EBinop(_, left, right):
				validateExpr(left, typeName, members, locals, functionDepth, loopDepth);
				validateExpr(right, typeName, members, locals, functionDepth, loopDepth);
			case EUnop(_, value) | EField(value, _) | ESafeField(value, _) | ECast(value, _) | EMeta(_, value):
				validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
			case ECall(callee, args):
				if (functionDepth == 0 && isAwaitCall(callee))
					fail("Static field initializers cannot suspend with HaxiomHost.await", expr.pos);
				validateExpr(callee, typeName, members, locals, functionDepth, loopDepth);
				for (arg in args)
					validateExpr(arg, typeName, members, locals, functionDepth, loopDepth);
			case EArrayDecl(values):
				for (value in values)
					validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
			case EObjectDecl(fields):
				for (field in fields)
					validateExpr(field.expr, typeName, members, locals, functionDepth, loopDepth);
			case EMapDecl(values):
				for (entry in values) {
					validateExpr(entry.key, typeName, members, locals, functionDepth, loopDepth);
					validateExpr(entry.value, typeName, members, locals, functionDepth, loopDepth);
				}
			case EBlock(exprs):
				var blockLocals = copyLocals(locals);
				for (child in exprs)
					validateExpr(child, typeName, members, blockLocals, functionDepth, loopDepth);
			case EFunction(_, args, _, body, _):
				var functionLocals = copyLocals(locals);
				for (arg in args)
					functionLocals.set(arg.name, true);
				validateExpr(body, typeName, members, functionLocals, functionDepth + 1, 0);
			case EIf(condition, thenExpr, elseExpr):
				validateExpr(condition, typeName, members, locals, functionDepth, loopDepth);
				validateExpr(thenExpr, typeName, members, copyLocals(locals), functionDepth, loopDepth);
				validateExpr(elseExpr, typeName, members, copyLocals(locals), functionDepth, loopDepth);
			case EWhile(condition, body) | EDoWhile(condition, body):
				validateExpr(condition, typeName, members, locals, functionDepth, loopDepth);
				validateExpr(body, typeName, members, copyLocals(locals), functionDepth, loopDepth + 1);
			case EFor(name, iterator, body):
				validateExpr(iterator, typeName, members, locals, functionDepth, loopDepth);
				var loopLocals = copyLocals(locals);
				loopLocals.set(name, true);
				validateExpr(body, typeName, members, loopLocals, functionDepth, loopDepth + 1);
			case ESwitch(value, cases, defaultExpr):
				validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
				for (item in cases) {
					for (pattern in item.values)
						validateExpr(pattern, typeName, members, locals, functionDepth, loopDepth);
					validateExpr(item.guard, typeName, members, locals, functionDepth, loopDepth);
					validateExpr(item.expr, typeName, members, copyLocals(locals), functionDepth, loopDepth);
				}
				validateExpr(defaultExpr, typeName, members, copyLocals(locals), functionDepth, loopDepth);
			case EReturn(value):
				if (functionDepth == 0)
					fail("Cannot return from a static field initializer", expr.pos);
				validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
			case EBreak | EContinue:
				if (loopDepth == 0)
					fail("Loop control is not valid outside a loop in a static field initializer", expr.pos);
			case EThrow(value):
				validateExpr(value, typeName, members, locals, functionDepth, loopDepth);
			case ETry(tryExpr, catches):
				validateExpr(tryExpr, typeName, members, copyLocals(locals), functionDepth, loopDepth);
				for (item in catches) {
					var catchLocals = copyLocals(locals);
					switch (item.pattern.def) {
						case EIdent(name): catchLocals.set(name, true);
						default: validateExpr(item.pattern, typeName, members, catchLocals, functionDepth, loopDepth);
					}
					validateExpr(item.guard, typeName, members, catchLocals, functionDepth, loopDepth);
					validateExpr(item.body, typeName, members, catchLocals, functionDepth, loopDepth);
				}
			case ENew(_, args):
				for (arg in args)
					validateExpr(arg, typeName, members, locals, functionDepth, loopDepth);
			case EClass(_, _, _, _, _, _, _, _) | EInterface(_, _, _, _, _, _) | EAbstract(_, _, _, _, _, _) | EEnum(_, _, _)
				| ETypedef(_, _, _) | EPackage(_) | EImport(_, _) | EUsing(_):
				fail("Type and module declarations are not valid inside a static field initializer", expr.pos);
		}
	}

	static function isAwaitCall(expr:Expr):Bool {
		return switch (expr.def) {
			case EField(owner, "await"):
				switch (owner.def) {
					case EIdent("HaxiomHost"): true;
					default: false;
				}
			default: false;
		};
	}

	static function copyLocals(source:Map<String, Bool>):Map<String, Bool> {
		var copy:Map<String, Bool> = new Map();
		for (name in source.keys())
			copy.set(name, true);
		return copy;
	}

	static function fail(message:String, pos:Pos):Void {
		throw new CompileException(message, pos != null ? pos.line : 1, pos != null ? pos.col : 1,
			pos != null && pos.file != null ? pos.file : "script");
	}
}
