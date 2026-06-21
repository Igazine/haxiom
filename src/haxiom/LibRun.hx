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
		var cleanArgs = [];
		for (arg in args) {
			if (arg == "--static" || arg == "--static-types") {
				enableStatic = true;
			} else {
				cleanArgs.push(arg);
			}
		}
		args = cleanArgs;

		if (args.length < 1) {
			Sys.println('Usage: haxelib run digigun.scripting.hx <command> <input> [--static]');
			Sys.exit(1);
		}
		var workingDir = args.pop();
		var command = args.shift();
		switch command.toLowerCase() {
			case 'bc':
				try {
					bytecodeCompile(workingDir, args.shift(), args.shift(), enableStatic);
				} catch (e:Dynamic) {
					Sys.println('Compilation error: ${e}');
					Sys.exit(1);
				}
			default:
				Sys.println('Unknown command\nUsage: haxelib run digigun.scripting.hx <command> <input> [--static]');
				Sys.exit(1);
		}
	}

	static function collectImports(e:Expr, imports:Array<String>) {
		if (e == null)
			return;
		switch (e.def) {
			case EImport(path, _):
				imports.push(path.join("."));
			case EBlock(exprs):
				for (expr in exprs)
					collectImports(expr, imports);
			case EIf(_, e1, e2):
				collectImports(e1, imports);
				collectImports(e2, imports);
			case EWhile(_, body):
				collectImports(body, imports);
			case EDoWhile(_, body):
				collectImports(body, imports);
			case EFor(_, _, body):
				collectImports(body, imports);
			case ESwitch(_, cases, defExpr):
				for (c in cases)
					collectImports(c.expr, imports);
				collectImports(defExpr, imports);
			case ETry(tryExpr, catches):
				collectImports(tryExpr, imports);
				for (c in catches)
					collectImports(c.body, imports);
			default:
		}
	}

	public static function bytecodeCompile(workingDir:String, input:String, ?key:String, ?staticTypes:Bool = false) {
		if (input == null) {
			throw 'Usage: haxelib run digigun.scripting.hx bc <input> <key> [--static]';
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
					compileSingleFile(workingDir, relFilePath, key, staticTypes);
				} catch (e:Dynamic) {
					Sys.println('Failed to compile ${relFilePath}: ${e}');
				}
			}
		} else {
			compileSingleFile(workingDir, input, key, staticTypes);
		}
	}

	static function compileSingleFile(workingDir:String, input:String, ?key:String, ?staticTypes:Bool = false) {
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

		final bytes = haxiom.compileASTToBytecodeBytes(optimizedAst, key != null ? new HXBCKey(key) : null);

		final output = haxe.io.Path.withoutExtension(input) + '.hxbc';
		File.saveBytes(workingDir + output, bytes);
		Sys.println('Successfully compiled and bundled ${input} to ${output} (${bytes.length} bytes)');
		Sys.println('Bundled modules in dependency order: ' + sorted.join(', '));
	}
}
