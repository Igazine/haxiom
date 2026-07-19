package haxiom;

import haxiom.AST;
import haxiom.HXBCKey;
import haxiom.Haxiom;
import haxiom.Lexer;
import haxiom.Parser;
import haxiom.StaticTypeChecker;
import sys.FileSystem;
import sys.io.File;

@:noDoc
@:noCompletion
class LibRun {
	static public function main() {
		var args = Sys.args();
		var enableStatic = false;
		var compress = false;
		var jsonMode = false;
		var cleanArgs = [];
		for (arg in args) {
			if (arg == "--static" || arg == "--static-types") {
				enableStatic = true;
			} else if (arg == "--compress" || arg == "-c") {
				compress = true;
			} else if (arg == "--json") {
				jsonMode = true;
			} else {
				cleanArgs.push(arg);
			}
		}
		args = cleanArgs;

		if (args.length < 1) {
			Sys.println('Usage: haxelib run haxiom <command> <input> [--static] [-c/--compress]');
			Sys.println('Commands: bc (bytecode compile), inspect (bytecode inspector)');
			Sys.exit(1);
		}
		var workingDir = args.pop();
		var command = args.shift();
		if (command == null) {
			Sys.println('Usage: haxelib run haxiom <command> <input> [--static] [-c/--compress]');
			Sys.exit(1);
		}
		switch command.toLowerCase() {
			case 'bc':
				try {
					bytecodeCompile(workingDir, args.shift(), args.shift(), enableStatic, compress);
				} catch (e:Dynamic) {
					Sys.println('Compilation error: ${e}');
					Sys.exit(1);
				}
			case 'inspect':
				try {
					bytecodeInspect(workingDir, args.shift(), args.shift(), jsonMode);
				} catch (e:Dynamic) {
					Sys.println('Inspection error: ${e}');
					Sys.exit(1);
				}
			default:
				Sys.println('Unknown command: ${command}\nUsage: haxelib run haxiom <command> <input> [--static] [-c/--compress]');
				Sys.exit(1);
		}
	}

	static function collectTypeImports(t:TypeDecl, imports:Array<String>) {
		if (t == null)
			return;
		switch (t) {
			case TPath(path, params):
				imports.push(path.join("."));
				for (p in params) {
					collectTypeImports(p, imports);
				}
			case TFun(args, ret):
				for (a in args) {
					collectTypeImports(a, imports);
				}
				collectTypeImports(ret, imports);
			case TAnonymous(fields):
				for (f in fields) {
					collectTypeImports(f.type, imports);
				}
		}
	}

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

	static function collectImports(e:Expr, imports:Array<String>) {
		if (e == null)
			return;

		var path = getExprPath(e);
		if (path != null) {
			var current = "";
			for (part in path) {
				if (current == "") {
					current = part;
				} else {
					current += "." + part;
				}
				imports.push(current);
			}
		}

		switch (e.def) {
			case EImport(path, _):
				imports.push(path.join("."));
			case EUsing(path):
				imports.push(path.join("."));
			case ENew(type, args):
				collectTypeImports(type, imports);
				for (arg in args) {
					collectImports(arg, imports);
				}
			case EVar(_, type, expr, _, meta):
				if (type != null) {
					collectTypeImports(type, imports);
				}
				if (expr != null) {
					collectImports(expr, imports);
				}
				if (meta != null) {
					for (m in meta) {
						for (p in m.params) {
							collectImports(p, imports);
						}
					}
				}
			case EAssign(target, expr):
				collectImports(target, imports);
				collectImports(expr, imports);
			case EBinop(_, e1, e2):
				collectImports(e1, imports);
				collectImports(e2, imports);
			case EUnop(_, expr):
				collectImports(expr, imports);
			case EField(objExpr, _):
				if (path == null) {
					collectImports(objExpr, imports);
				}
			case ESafeField(objExpr, _):
				if (path == null) {
					collectImports(objExpr, imports);
				}
			case ECall(callExpr, args):
				collectImports(callExpr, imports);
				for (arg in args) {
					collectImports(arg, imports);
				}
			case EArrayDecl(values):
				for (v in values) {
					collectImports(v, imports);
				}
			case EObjectDecl(fields):
				for (f in fields) {
					collectImports(f.expr, imports);
				}
			case EMapDecl(values):
				for (pair in values) {
					collectImports(pair.key, imports);
					collectImports(pair.value, imports);
				}
			case EBlock(exprs):
				for (expr in exprs) {
					collectImports(expr, imports);
				}
			case EFunction(_, args, retType, body):
				for (arg in args) {
					if (arg.type != null) {
						collectTypeImports(arg.type, imports);
					}
				}
				if (retType != null) {
					collectTypeImports(retType, imports);
				}
				collectImports(body, imports);
			case EIf(cond, e1, e2):
				collectImports(cond, imports);
				collectImports(e1, imports);
				if (e2 != null) {
					collectImports(e2, imports);
				}
			case EWhile(cond, body):
				collectImports(cond, imports);
				collectImports(body, imports);
			case EDoWhile(cond, body):
				collectImports(cond, imports);
				collectImports(body, imports);
			case EFor(_, it, body):
				collectImports(it, imports);
				collectImports(body, imports);
			case ESwitch(expr, cases, defExpr):
				collectImports(expr, imports);
				for (c in cases) {
					for (v in c.values) {
						collectImports(v, imports);
					}
					if (c.guard != null) {
						collectImports(c.guard, imports);
					}
					collectImports(c.expr, imports);
				}
				if (defExpr != null) {
					collectImports(defExpr, imports);
				}
			case EReturn(expr):
				if (expr != null) {
					collectImports(expr, imports);
				}
			case EThrow(expr):
				collectImports(expr, imports);
			case ETry(tryExpr, catches):
				collectImports(tryExpr, imports);
				for (c in catches) {
					if (c.type != null) {
						collectTypeImports(c.type, imports);
					}
					if (c.guard != null) {
						collectImports(c.guard, imports);
					}
					collectImports(c.body, imports);
				}
			case ECast(expr, type):
				collectImports(expr, imports);
				if (type != null) {
					collectTypeImports(type, imports);
				}
			case EClass(_, fields, methods, parent, interfaces, _, meta):
				if (parent != null) {
					collectTypeImports(parent, imports);
				}
				if (interfaces != null) {
					for (inf in interfaces) {
						collectTypeImports(inf, imports);
					}
				}
				if (meta != null) {
					for (m in meta) {
						for (p in m.params) {
							collectImports(p, imports);
						}
					}
				}
				for (f in fields) {
					if (f.type != null) {
						collectTypeImports(f.type, imports);
					}
					if (f.expr != null) {
						collectImports(f.expr, imports);
					}
					if (f.meta != null) {
						for (m in f.meta) {
							for (p in m.params) {
								collectImports(p, imports);
							}
						}
					}
				}
				for (m in methods) {
					for (arg in m.args) {
						if (arg.type != null) {
							collectTypeImports(arg.type, imports);
						}
					}
					if (m.retType != null) {
						collectTypeImports(m.retType, imports);
					}
					if (m.body != null) {
						collectImports(m.body, imports);
					}
					if (m.meta != null) {
						for (mt in m.meta) {
							for (p in mt.params) {
								collectImports(p, imports);
							}
						}
					}
				}
			case EInterface(_, fields, methods, parents, _, meta):
				if (parents != null) {
					for (p in parents) {
						collectTypeImports(p, imports);
					}
				}
				if (meta != null) {
					for (m in meta) {
						for (p in m.params) {
							collectImports(p, imports);
						}
					}
				}
				for (f in fields) {
					if (f.type != null) {
						collectTypeImports(f.type, imports);
					}
					if (f.meta != null) {
						for (m in f.meta) {
							for (p in m.params) {
								collectImports(p, imports);
							}
						}
					}
				}
				for (m in methods) {
					for (arg in m.args) {
						if (arg.type != null) {
							collectTypeImports(arg.type, imports);
						}
					}
					if (m.retType != null) {
						collectTypeImports(m.retType, imports);
					}
					if (m.body != null) {
						collectImports(m.body, imports);
					}
					if (m.meta != null) {
						for (mt in m.meta) {
							for (p in mt.params) {
								collectImports(p, imports);
							}
						}
					}
				}
			case EEnum(_, constructors, _):
				for (c in constructors) {
					if (c.args != null) {
						for (arg in c.args) {
							if (arg.type != null) {
								collectTypeImports(arg.type, imports);
							}
						}
					}
				}
			case EAbstract(_, underlyingType, fields, methods, _, meta):
				collectTypeImports(underlyingType, imports);
				if (meta != null) {
					for (m in meta) {
						for (p in m.params) {
							collectImports(p, imports);
						}
					}
				}
				for (f in fields) {
					if (f.type != null) {
						collectTypeImports(f.type, imports);
					}
					if (f.expr != null) {
						collectImports(f.expr, imports);
					}
					if (f.meta != null) {
						for (m in f.meta) {
							for (p in m.params) {
								collectImports(p, imports);
							}
						}
					}
				}
				for (m in methods) {
					for (arg in m.args) {
						if (arg.type != null) {
							collectTypeImports(arg.type, imports);
						}
					}
					if (m.retType != null) {
						collectTypeImports(m.retType, imports);
					}
					if (m.body != null) {
						collectImports(m.body, imports);
					}
					if (m.meta != null) {
						for (mt in m.meta) {
							for (p in mt.params) {
								collectImports(p, imports);
							}
						}
					}
				}
			case ETypedef(_, type, _):
				collectTypeImports(type, imports);
			case EMeta(meta, expr):
				for (m in meta) {
					for (p in m.params) {
						collectImports(p, imports);
					}
				}
				collectImports(expr, imports);
			default:
		}
	}

	public static function bytecodeCompile(workingDir:String, input:String, ?key:String, ?staticTypes:Bool = false, ?compress:Bool = false) {
		if (input == null) {
			throw 'Usage: haxelib run haxiom bc <input> [key] [--static] [-c/--compress]';
		}

		// Normalize workingDir to ensure trailing slash
		if (workingDir != "" && !StringTools.endsWith(workingDir, "/") && !StringTools.endsWith(workingDir, "\\")) {
			workingDir += "/";
		}

		var fullInputPath = workingDir + input;
		if (!FileSystem.exists(fullInputPath)) {
			throw 'Input path not found: ' + fullInputPath;
		}

		if (FileSystem.isDirectory(fullInputPath)) {
			var filesToCompile = [];
			function collectHxFiles(dir:String) {
				for (entry in FileSystem.readDirectory(dir)) {
					var path = dir + "/" + entry;
					if (FileSystem.isDirectory(path)) {
						collectHxFiles(path);
					} else if (StringTools.endsWith(entry.toLowerCase(), ".hx")) {
						filesToCompile.push(path);
					}
				}
			}
			collectHxFiles(fullInputPath);

			Sys.println('Found ' + filesToCompile.length + ' Haxe files to compile in directory: ' + input);
			for (file in filesToCompile) {
				var relFilePath = file;
				if (StringTools.startsWith(file, workingDir)) {
					relFilePath = file.substring(workingDir.length);
				}
				try {
					compileSingleFile(workingDir, relFilePath, key, staticTypes, compress);
				} catch (e:Dynamic) {
					Sys.println('Failed to compile ${relFilePath}: ${e}');
				}
			}
		} else {
			compileSingleFile(workingDir, input, key, staticTypes, compress);
		}
	}

	static function compileSingleFile(workingDir:String, input:String, ?key:String, ?staticTypes:Bool = false, ?compress:Bool = false) {
		var fullInputPath = workingDir + input;
		final haxiom = new Haxiom();
		haxiom.enableStaticTypes = staticTypes;
		var source = File.getContent(fullInputPath);

		// Parse the main file to extract its package and start bundling
		var lexer = new Lexer(source, input, haxiom.preprocessorFlags);
		var tokens = lexer.tokenize();
		var parser = new Parser(tokens, input);
		var initialAst = parser.parse();

		// Find package declaration of the main file
		var pkgPath:Array<String> = [];
		switch (initialAst.def) {
			case EBlock(exprs):
				for (e in exprs) {
					switch (e.def) {
						case EPackage(path):
							pkgPath = path;
							break;
						default:
					}
				}
			default:
		}

		// Deduce the local source path context (classpath root directory)
		var fileDir = haxe.io.Path.directory(fullInputPath);
		var sourceRoot = fileDir;
		for (i in 0...pkgPath.length) {
			sourceRoot = haxe.io.Path.directory(sourceRoot);
		}
		if (sourceRoot != "" && !StringTools.endsWith(sourceRoot, "/") && !StringTools.endsWith(sourceRoot, "\\")) {
			sourceRoot += "/";
		}

		// Recursive module resolution
		var modules = new Map<String, {
			fqName:String,
			path:String,
			ast:Expr,
			dependencies:Array<String>
		}>();
		var pending = [fullInputPath];
		var parsedFiles = new Map<String, Bool>();
		parsedFiles.set(haxe.io.Path.normalize(fullInputPath), true);

		while (pending.length > 0) {
			var currentPath = pending.shift();

			// Read and parse the file
			var src = File.getContent(currentPath);
			var relativePathForLexer = currentPath;
			if (StringTools.startsWith(currentPath, workingDir)) {
				relativePathForLexer = currentPath.substring(workingDir.length);
			}

			var currentLexer = new Lexer(src, relativePathForLexer, haxiom.preprocessorFlags);
			var currentTokens = currentLexer.tokenize();
			var currentParser = new Parser(currentTokens, relativePathForLexer);
			var ast = currentParser.parse();

			var pkg:Array<String> = [];
			var moduleName = haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(currentPath));

			switch (ast.def) {
				case EBlock(exprs):
					for (e in exprs) {
						switch (e.def) {
							case EPackage(p):
								pkg = p;
								break;
							default:
						}
					}
				default:
			}

			var fqName = pkg.length > 0 ? pkg.join(".") + "." + moduleName : moduleName;

			var deps = [];
			var collected = [];
			collectImports(ast, collected);

			for (imp in collected) {
				// Check local file existence under sourceRoot or workingDir
				var impRelPath = imp.split(".").join("/") + ".hx";
				var localPath = sourceRoot + impRelPath;
				var fallbackPath = workingDir + impRelPath;

				var resolvedPath:String = null;
				if (FileSystem.exists(localPath)) {
					resolvedPath = localPath;
				} else if (FileSystem.exists(fallbackPath)) {
					resolvedPath = fallbackPath;
				}

				if (resolvedPath != null) {
					var normPath = haxe.io.Path.normalize(resolvedPath);
					deps.push(imp);
					if (!parsedFiles.exists(normPath)) {
						parsedFiles.set(normPath, true);
						pending.push(resolvedPath);
					}
				}
			}

			modules.set(fqName, {
				fqName: fqName,
				path: currentPath,
				ast: ast,
				dependencies: deps
			});
		}

		// Topological Sort (dependencies first, main file last)
		var sorted = [];
		var visited = new Map<String, Bool>();
		var temp = new Map<String, Bool>();

		function visit(nodeFq:String) {
			if (temp.exists(nodeFq)) {
				throw "Circular dependency detected: " + nodeFq;
			}
			if (!visited.exists(nodeFq)) {
				temp.set(nodeFq, true);
				var node = modules.get(nodeFq);
				if (node != null) {
					for (dep in node.dependencies) {
						visit(dep);
					}
				}
				temp.remove(nodeFq);
				visited.set(nodeFq, true);
				sorted.push(nodeFq);
			}
		}

		// Determine the main module's FQ name
		var mainModuleName = haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(fullInputPath));
		var mainFqName = pkgPath.length > 0 ? pkgPath.join(".") + "." + mainModuleName : mainModuleName;
		visit(mainFqName);

		// Combine ASTs
		var combinedExprs = [];
		for (fq in sorted) {
			var mod = modules.get(fq);
			if (mod != null) {
				switch (mod.ast.def) {
					case EBlock(exprs):
						for (e in exprs) {
							combinedExprs.push(e);
						}
					default:
						combinedExprs.push(mod.ast);
				}
			}
		}

		var combinedAst = {def: EBlock(combinedExprs), pos: {line: 1, col: 1}};

		// Append main() execution trigger if present in the main module
		combinedAst = Haxiom.appendMainCallIfPresent(combinedAst, mainModuleName);

		// Apply the full optimization pipeline (constant folding + DCE) before serializing
		var optimizedAst = Optimizer.foldConstants(combinedAst);
		if (haxiom.enableDCE) {
			optimizedAst = Optimizer.eliminateDeadCode(optimizedAst);
		}

		if (haxiom.enableStaticTypes) {
			StaticTypeChecker.check(optimizedAst, haxiom.interp);
		}

		final bytes = haxiom.compileASTToBytecodeBytes(optimizedAst, key != null ? new HXBCKey(key) : null, false, compress);

		final output = haxe.io.Path.withoutExtension(input) + '.hxbc';
		File.saveBytes(workingDir + output, bytes);
		var compMsg = compress ? ' [LZ4 Compressed]' : '';
		Sys.println('Successfully compiled and bundled ${input} to ${output} (${bytes.length} bytes)${compMsg}');
		Sys.println('Bundled modules in dependency order: ' + sorted.join(', '));
	}

	public static function bytecodeInspect(workingDir:String, inputFile:String, ?keyStr:String, ?isJsonFlag:Bool = false) {
		var envJson = Sys.getEnv("HAXIOM_INSPECT_JSON");
		var isJson = isJsonFlag || (envJson == "1" || envJson == "true");

		if (inputFile == null) {
			if (isJson) {
				Sys.println(haxe.Json.stringify({error: "Usage: haxelib run haxiom inspect <hxbc_file> [key] [--json]", status: "ERROR"}, "  "));
			} else {
				Sys.println('Usage: haxelib run haxiom inspect <hxbc_file> [key] [--json]');
			}
			Sys.exit(1);
		}

		var fullPath = workingDir + inputFile;
		if (!FileSystem.exists(fullPath)) {
			fullPath = inputFile;
			if (!FileSystem.exists(fullPath)) {
				if (isJson) {
					Sys.println(haxe.Json.stringify({filePath: inputFile, error: 'File not found: ${inputFile}', status: "ERROR"}, "  "));
				} else {
					Sys.println('Error: File not found: ${inputFile}');
				}
				Sys.exit(1);
			}
		}

		var bytes = File.getBytes(fullPath);
		if (bytes.length < 18) {
			if (isJson) {
				Sys.println(haxe.Json.stringify({filePath: inputFile, error: 'File is not a valid HXBC file (too short)', status: "ERROR"}, "  "));
			} else {
				Sys.println('Error: File is not a valid HXBC file (too short)');
			}
			Sys.exit(1);
		}

		var input = new haxe.io.BytesInput(bytes);
		input.bigEndian = false;
		var magic = input.readString(4);
		if (magic != "HXBC") {
			if (isJson) {
				Sys.println(haxe.Json.stringify({filePath: inputFile, error: 'Invalid magic header: ${magic}', status: "ERROR"}, "  "));
			} else {
				Sys.println('Error: File is not a valid HXBC file (invalid magic: ' + magic + ')');
			}
			Sys.exit(1);
		}

		var version = input.readByte();
		var flags = input.readByte();
		var isAsync = (flags & 1) == 1;
		var isEncrypted = (flags & 2) == 2;
		var isCompressed = (flags & 4) == 4;
		var maxSlots = input.readInt32();
		var uncompressedSize = input.readInt32();
		var checksum = input.readInt32();
		var checksumHex = '0x' + StringTools.hex(checksum, 8);
		var payloadCompressedSize = bytes.length - 18;
		var savingPct = (isCompressed && uncompressedSize > 0) ? Math.round((1.0 - (payloadCompressedSize / uncompressedSize)) * 1000) / 10.0 : 0.0;

		var key:HXBCKey = keyStr != null ? new HXBCKey(keyStr) : null;
		if (isEncrypted && (key == null || !key.isValid())) {
			if (isJson) {
				Sys.println(haxe.Json.stringify({
					filePath: inputFile,
					fileSize: bytes.length,
					uncompressedPayloadSize: uncompressedSize,
					compressionRatio: isCompressed ? '${savingPct}%' : '0%',
					version: version,
					maxSlots: maxSlots,
					isAsync: isAsync,
					isEncrypted: true,
					isCompressed: isCompressed,
					checksum: checksumHex,
					error: "Payload is encrypted. Provide decryption key to inspect internal payload details.",
					status: "ENCRYPTED"
				}, "  "));
			} else {
				Sys.println("==================================================");
				Sys.println("              HAXIOM HXBC INSPECTOR               ");
				Sys.println("==================================================");
				Sys.println(' File Path:                 ${inputFile}');
				Sys.println(' Total File Size (Disk):    ${bytes.length} bytes');
				Sys.println(' Uncompressed Payload Size: ${uncompressedSize} bytes');
				if (isCompressed) {
					Sys.println(' LZ4 Compression Ratio:     ${savingPct}% saved');
				}
				Sys.println(' HXBC Version:              ${version}');
				Sys.println(' Max Slots Required:        ${maxSlots}');
				Sys.println(' Asynchronous:             ${isAsync ? "YES" : "NO"}');
				Sys.println(' Encrypted:                 YES');
				Sys.println(' LZ4 Compressed:            ${isCompressed ? "YES" : "NO"}');
				Sys.println(' Checksum:                  ${checksumHex}');
				Sys.println("--------------------------------------------------");
				Sys.println(" [!] Payload is encrypted. Provide decryption key to inspect internal payload details.");
				Sys.println(" Usage: haxelib run haxiom inspect <hxbc_file> <key>");
			}
			return;
		}

		try {
			var chunk = Serializer.deserializeBytecode(bytes, key);
			var instCount = chunk.instructions != null ? chunk.instructions.length : 0;
			var posCount = chunk.positions != null ? chunk.positions.length : 0;
			var debugCount = chunk.debugSymbols != null ? chunk.debugSymbols.length : 0;
			var constCount = chunk.constants != null ? chunk.constants.length : 0;

			// Extract source files and type declarations
			var extractedData = extractChunkMetadata(chunk);

			if (isJson) {
				var jsonResult:Dynamic = {
					filePath: inputFile,
					fileSize: bytes.length,
					uncompressedPayloadSize: uncompressedSize,
					compressionRatio: isCompressed ? '${savingPct}%' : '0%',
					version: version,
					maxSlots: maxSlots,
					isAsync: isAsync,
					isEncrypted: isEncrypted,
					isCompressed: isCompressed,
					checksum: checksumHex,
					instructionCount: instCount,
					constantPoolSize: constCount,
					debugSymbolCount: debugCount,
					positionMappingCount: posCount,
					debugSymbols: chunk.debugSymbols != null ? chunk.debugSymbols.map(s -> {slot: s.slot, name: s.name, startIp: s.startIp, endIp: s.endIp}) : [],
					sourceFiles: extractedData.sourceFiles,
					compiledTypes: extractedData.compiledTypes,
					status: "VALID"
				};
				Sys.println(haxe.Json.stringify(jsonResult, "  "));
			} else {
				Sys.println("==================================================");
				Sys.println("              HAXIOM HXBC INSPECTOR               ");
				Sys.println("==================================================");
				Sys.println(' File Path:                 ${inputFile}');
				Sys.println(' Total File Size (Disk):    ${bytes.length} bytes');
				Sys.println(' Uncompressed Payload Size: ${uncompressedSize} bytes');
				if (isCompressed) {
					Sys.println(' LZ4 Compression Ratio:     ${savingPct}% saved');
				}
				Sys.println(' HXBC Version:              ${version}');
				Sys.println(' Max Slots Required:        ${maxSlots}');
				Sys.println(' Asynchronous:             ${isAsync ? "YES" : "NO"}');
				Sys.println(' Encrypted:                 ${isEncrypted ? "YES" : "NO"}');
				Sys.println(' LZ4 Compressed:            ${isCompressed ? "YES" : "NO"}');
				Sys.println(' Checksum:                  ${checksumHex}');
				Sys.println("--------------------------------------------------");
				Sys.println(' Instruction Count:         ${instCount}');
				Sys.println(' Constant Pool Size:        ${constCount}');
				Sys.println(' Debug Symbols:             ${debugCount}');
				Sys.println(' Position Mapping:          ${posCount} entries');
				Sys.println("--------------------------------------------------");

				if (chunk.debugSymbols != null && chunk.debugSymbols.length > 0) {
					Sys.println(" Debug Symbols & Local Variables:");
					for (sym in chunk.debugSymbols) {
						Sys.println('   - Slot ${sym.slot}: "${sym.name}" (start PC: ${sym.startIp}, end PC: ${sym.endIp})');
					}
					Sys.println("--------------------------------------------------");
				}

				if (extractedData.sourceFiles.length > 0) {
					Sys.println(' Included Source Files (${extractedData.sourceFiles.length}):');
					for (f in extractedData.sourceFiles) {
						Sys.println('   * ${f}');
					}
					Sys.println("--------------------------------------------------");
				}

				if (extractedData.typeSummaries.length > 0) {
					Sys.println(' Compiled Script Types & Declarations (${extractedData.typeSummaries.length}):');
					for (t in extractedData.typeSummaries) {
						Sys.println('   + ${t}');
					}
					Sys.println("--------------------------------------------------");
				}

				Sys.println(" Bytecode Status:    VALID & SUITABLE FOR HOST RUNTIME");
				Sys.println("==================================================");
			}
		} catch (e:Dynamic) {
			if (isJson) {
				Sys.println(haxe.Json.stringify({filePath: inputFile, error: 'Error inspecting payload: ${e}', status: "ERROR"}, "  "));
			} else {
				Sys.println(' [!] Error inspecting payload: ${e}');
			}
		}
	}

	static function extractChunkMetadata(chunk:haxiom.VM.BytecodeChunk):{sourceFiles:Array<String>, typeSummaries:Array<String>, compiledTypes:Array<Dynamic>} {
		var filesMap = new Map<String, Bool>();
		var sourceFiles = [];
		if (chunk.positions != null) {
			for (p in chunk.positions) {
				if (p != null && p.file != null && p.file.length > 0) {
					if (!filesMap.exists(p.file)) {
						filesMap.set(p.file, true);
						sourceFiles.push(p.file);
					}
				}
			}
		}

		var typeSummaries = [];
		var compiledTypes:Array<Dynamic> = [];
		if (chunk.constants != null) {
			for (c in chunk.constants) {
				if (c != null && Reflect.hasField(c, "def")) {
					var e:Expr = cast c;
					switch (e.def) {
						case EPackage(path):
							var pkgName = path.join(".");
							typeSummaries.push('package ${pkgName}');
							compiledTypes.push({kind: "package", name: pkgName});

						case EClass(name, fields, methods, parent, interfaces, params, meta):
							var parentName:String = null;
							if (parent != null) {
								switch (parent) {
									case TPath(pPath, _): parentName = pPath.join(".");
									default:
								}
							}
							var itfNames = [];
							if (interfaces != null && interfaces.length > 0) {
								for (itf in interfaces) {
									switch (itf) {
										case TPath(iPath, _): itfNames.push(iPath.join("."));
										default:
									}
								}
							}
							var mNames = [for (m in methods) m.name];
							var details = 'class ${name}';
							if (parentName != null) details += ' extends ${parentName}';
							if (itfNames.length > 0) details += ' implements ${itfNames.join(", ")}';
							details += ' [${fields.length} fields, ${methods.length} methods: ${mNames.join(", ")}]';

							typeSummaries.push(details);
							compiledTypes.push({
								kind: "class",
								name: name,
								parent: parentName,
								interfaces: itfNames,
								fieldCount: fields.length,
								methodCount: methods.length,
								methods: mNames
							});

						case EInterface(name, fields, methods, parents, params, meta):
							var mNames = [for (m in methods) m.name];
							typeSummaries.push('interface ${name} [${methods.length} methods: ${mNames.join(", ")}]');
							compiledTypes.push({
								kind: "interface",
								name: name,
								methodCount: methods.length,
								methods: mNames
							});

						case EEnum(name, constructors, params):
							var ctorNames = [for (ctor in constructors) ctor.name];
							typeSummaries.push('enum ${name} [${constructors.length} ctors: ${ctorNames.join(", ")}]');
							compiledTypes.push({
								kind: "enum",
								name: name,
								constructorCount: constructors.length,
								constructors: ctorNames
							});

						case EAbstract(name, underlyingType, fields, methods, params, meta):
							typeSummaries.push('abstract ${name} [${fields.length} fields, ${methods.length} methods]');
							compiledTypes.push({
								kind: "abstract",
								name: name,
								fieldCount: fields.length,
								methodCount: methods.length
							});

						case ETypedef(name, type, params):
							typeSummaries.push('typedef ${name}');
							compiledTypes.push({
								kind: "typedef",
								name: name
							});

						default:
					}
				}
			}
		}

		return {
			sourceFiles: sourceFiles,
			typeSummaries: typeSummaries,
			compiledTypes: compiledTypes
		};
	}
}
