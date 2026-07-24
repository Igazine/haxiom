package haxiom;

import haxiom.AST;
import haxe.io.Bytes;

/**
 * Helper class for processing `@:haxiom.resource('./path')` metadata annotations.
 * Supports embedded binary payloads, virtual resources map,
 * custom host resource provider callbacks, and disk loading on sys targets.
 */
@:allow(haxiom)
class ResourceCompiler {
	/** Global virtual resources map for host-injected memory assets */
	private static var virtualResources:Map<String, Bytes> = new Map();

	/** Custom host resource provider function */
	private static var resourceProvider:Null<(path:String) -> Bytes> = null;

	private static function loadResourceBytes(relPath:String, pos:Pos):Bytes {
		var pStr = pos != null ? '${pos.file != null ? pos.file : "script"}:${pos.line}:${pos.col}' : "script";

		// 1. Check virtual resources map
		if (virtualResources.exists(relPath)) {
			return virtualResources.get(relPath);
		}

		// 2. Check custom host resource provider
		if (resourceProvider != null) {
			var res = resourceProvider(relPath);
			if (res != null)
				return res;
		}

		// 3. Check haxe.Resource embedded items
		try {
			var hRes = haxe.Resource.getBytes(relPath);
			if (hRes != null)
				return hRes;
		} catch (e:Dynamic) {}

		// 4. FileSystem disk loading on sys targets
		#if sys
		var fullPath = relPath;
		if (pos != null && pos.file != null && pos.file.length > 0) {
			var dir = haxe.io.Path.directory(pos.file);
			if (dir != null && dir.length > 0) {
				var p = haxe.io.Path.join([dir, relPath]);
				if (sys.FileSystem.exists(p)) {
					fullPath = p;
				}
			}
		}
		if (sys.FileSystem.exists(fullPath)) {
			return sys.io.File.getBytes(fullPath);
		}
		if (sys.FileSystem.exists(relPath)) {
			return sys.io.File.getBytes(relPath);
		}
		#end

		throw 'Compile Error: Resource file not found: \'${relPath}\' at ${pStr}';
	}

	private static function processResource(meta:Null<Array<{name:String, params:Array<Expr>}>>, type:Null<TypeDecl>, expr:Null<Expr>, pos:Pos,
			resourcesMap:Map<String, Bytes>):Null<Expr> {
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
			case EValue(v):
				relPath = Std.string(v);
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

		// Load resource bytes via target-agnostic resolver
		var fileBytes = loadResourceBytes(relPath, pos);

		// Validation 2: Explicit initializer check (verify expr matches synthesized resource value)
		if (expr != null) {
			switch (expr.def) {
				case EValue(v):
					if (isString) {
						if (v != fileBytes.toString()) {
							throw 'Compile Error: Field marked with @:haxiom.resource cannot have an explicit initializer at ${pStr}';
						}
					} else {
						if (!Std.isOfType(v, Bytes) && !Std.isOfType(v, BinaryResourceRefHolder)) {
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
			return {def: EValue(new BinaryResourceRefHolder(relPath)), pos: pos};
		}
	}
}
