package haxiom;

import haxiom.AST;
import haxe.io.Bytes;

/**
 * Helper class for processing `@:haxiom.resource('./path')` metadata annotations.
 * Handles compile-time file disk resolution, missing file checks, explicit initializer checks,
 * UTF-8 String vs raw Bytes type conversion, and resource table bundling.
 */
class ResourceCompiler {
	public static function processResource(
		meta:Null<Array<{name:String, params:Array<Expr>}>>,
		type:Null<TypeDecl>,
		expr:Null<Expr>,
		pos:Pos,
		resourcesMap:Map<String, Bytes>
	):Null<Expr> {
		if (meta == null)
			return expr;

		var resourceMeta:Null<{name:String, params:Array<Expr>}> = null;
		for (m in meta) {
			if (m != null && (m.name == ":haxiom.resource" || m.name == "haxiom.resource" || m.name == "@:haxiom.resource")) {
				resourceMeta = m;
				break;
			}
		}

		if (resourceMeta == null)
			return expr;

		var pStr = pos != null ? '${pos.file != null ? pos.file : "script"}:${pos.line}:${pos.col}' : "script";

		// Validation 1: Missing path parameter check
		if (resourceMeta.params == null || resourceMeta.params.length == 0) {
			throw 'Compile Error: @:haxiom.resource metadata requires a resource path string argument at ${pStr}';
		}

		var relPath:String = null;
		switch (resourceMeta.params[0].def) {
			case EValue(v): relPath = Std.string(v);
			default:
				throw 'Compile Error: @:haxiom.resource path argument must be a string literal at ${pStr}';
		}

		if (relPath == null || relPath.length == 0) {
			throw 'Compile Error: Invalid resource path in @:haxiom.resource at ${pStr}';
		}

		// Determine if field type is String
		var isString = false;
		if (type != null) {
			switch (type) {
				case TPath(path, _):
					if (path != null && path.length > 0 && path[path.length - 1] == "String") {
						isString = true;
					}
				default:
			}
		}

		// Resolve file bytes from disk (requires sys target or AOT compilation to .hxbc)
		var fileBytes:Bytes = null;
		#if sys
		var fullPath = relPath;
		if (pos != null && pos.file != null && pos.file.length > 0) {
			var dir = haxe.io.Path.directory(pos.file);
			if (dir != null && dir.length > 0) {
				var resolved = haxe.io.Path.join([dir, relPath]);
				if (sys.FileSystem.exists(resolved)) {
					fullPath = resolved;
				}
			}
		}

		if (!sys.FileSystem.exists(fullPath)) {
			if (sys.FileSystem.exists(relPath)) {
				fullPath = relPath;
			} else {
				throw 'Compile Error: Resource file not found: \'${relPath}\' at ${pStr}';
			}
		}

		fileBytes = sys.io.File.getBytes(fullPath);
		#else
		throw 'Compile Error: Direct disk resource loading via @:haxiom.resource is not supported on non-sys targets (e.g. Browser JS). Compile scripts ahead-of-time to .hxbc bytecode format using `haxelib run haxiom bc` at ${pStr}';
		#end

		// Validation 2: Explicit initializer check (verify expr matches synthesized resource value)
		if (expr != null) {
			switch (expr.def) {
				case EValue(v):
					if (isString) {
						if (v != fileBytes.toString()) {
							throw 'Compile Error: Field marked with @:haxiom.resource cannot have an explicit initializer at ${pStr}';
						}
					} else {
						if (!Std.isOfType(v, Bytes)) {
							throw 'Compile Error: Field marked with @:haxiom.resource cannot have an explicit initializer at ${pStr}';
						}
					}
				default:
					throw 'Compile Error: Field marked with @:haxiom.resource cannot have an explicit initializer at ${pStr}';
			}
		}

		if (resourcesMap != null) {
			resourcesMap.set(relPath, fileBytes);
		}

		if (isString) {
			var utf8Str = fileBytes.toString();
			return {def: EValue(utf8Str), pos: pos};
		} else {
			return {def: EValue(fileBytes), pos: pos};
		}
	}
}
