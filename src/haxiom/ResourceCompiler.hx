package haxiom;

import haxiom.AST;
import haxe.io.Bytes;

/**
 * Helper class for processing `@:haxiom.resource('./path')` metadata annotations.
 * Supports embedded binary payloads, virtual resources map,
 * custom host resource provider callbacks, and host-compiled `haxe.Resource` data.
 */
@:allow(haxiom)
class ResourceCompiler {
	private static function loadResourceBytes(interp:Interp, relPath:String, pos:Pos):Bytes {
		var pStr = pos != null ? '${pos.file != null ? pos.file : "script"}:${pos.line}:${pos.col}' : "script";
		var contextualPath = relPath;
		if (pos != null && pos.file != null && pos.file.length > 0) {
			var dir = haxe.io.Path.directory(pos.file);
			if (dir != null && dir.length > 0) {
				contextualPath = haxe.io.Path.normalize(haxe.io.Path.join([dir, relPath]));
			}
		}

		// 1. Check virtual resources map on interp instance
		if (interp != null && interp.virtualResources != null && interp.virtualResources.exists(relPath)) {
			return interp.virtualResources.get(relPath);
		}
		if (interp != null && interp.virtualResources != null && contextualPath != relPath && interp.virtualResources.exists(contextualPath)) {
			return interp.virtualResources.get(contextualPath);
		}

		// 2. Check custom host resource provider on interp instance
		if (interp != null && interp.resourceProvider != null) {
			var res = interp.resourceProvider(relPath);
			if (res != null)
				return res;
			if (contextualPath != relPath) {
				res = interp.resourceProvider(contextualPath);
				if (res != null)
					return res;
			}
		}

		// 3. Check haxe.Resource embedded items
		try {
			var hRes = haxe.Resource.getBytes(relPath);
			if (hRes != null)
				return hRes;
		} catch (e:Dynamic) {}
		if (contextualPath != relPath) {
			try {
				var contextualResource = haxe.Resource.getBytes(contextualPath);
				if (contextualResource != null)
					return contextualResource;
			} catch (e:Dynamic) {}
		}

		throw 'Compile Error: Resource file not found: \'${relPath}\' at ${pStr}';
	}

	private static function processResource(interp:Interp, meta:Null<Array<{name:String, params:Array<Expr>}>>, type:Null<TypeDecl>, expr:Null<Expr>, pos:Pos,
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
		var fileBytes = loadResourceBytes(interp, relPath, pos);

		// Validation 2: explicit initializers are not allowed on resource fields.
		// The compiler owns the initializer so binary/text resources cannot be shadowed.
		if (expr != null) {
			throw 'Compile Error: Field marked with @:haxiom.resource cannot have an explicit initializer at ${pStr}';
		}

		if (isString) {
			var utf8Str = fileBytes.toString();
			return {def: EValue(utf8Str), pos: pos};
		} else if (resourcesMap != null) {
			resourcesMap.set(relPath, fileBytes);
			return {def: EValue(new BinaryResourceRefHolder(relPath)), pos: pos};
		} else {
			return {def: EValue(fileBytes), pos: pos};
		}
	}
}
