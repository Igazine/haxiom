package haxiom;

import haxiom.AST.TypeDecl;
import haxiom.Interp.Scope;
import haxiom.HaxiomTypes.ClassMethodInfo;
import haxiom.HaxiomTypes.HaxiomClass;
import haxiom.HaxiomTypes.HaxiomInstance;
import haxiom.HaxiomTypes.HaxiomInterface;
import haxiom.HaxiomTypes.HaxiomEnum;
import haxiom.HaxiomTypes.HaxiomEnumInstance;
import haxiom.HaxiomTypes.HaxiomAbstract;
import haxiom.HaxiomTypes.HaxiomAbstractInstance;

@:allow(haxiom)
class TypeSystem {
	static function isHaxiomInstance(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomInstance) || (Reflect.hasField(val, "cls") && Reflect.hasField(val, "fields")
			&& Std.isOfType(Reflect.field(val, "cls"), HaxiomClass)));
	}

	static function isHaxiomAbstractInstance(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomAbstractInstance) || (Reflect.hasField(val, "abstractType") && Reflect.hasField(val, "underlyingValue")
			&& Std.isOfType(Reflect.field(val, "abstractType"), HaxiomAbstract)));
	}

	static function isHaxiomEnumInstance(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomEnumInstance) || (Reflect.hasField(val, "enumType") && Reflect.hasField(val, "constructorName")
			&& Std.isOfType(Reflect.field(val, "enumType"), HaxiomEnum)));
	}

	static function isHaxiomGuestType(val:Dynamic):Bool {
		return val != null && (isHaxiomClass(val) || isHaxiomInterface(val) || isHaxiomEnum(val) || isHaxiomAbstract(val));
	}

	static function isHaxiomClass(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomClass) || (Reflect.hasField(val, "name") && Reflect.hasField(val, "methods")
			&& Reflect.hasField(val, "staticFields") && Reflect.hasField(val, "interfaces")));
	}

	static function isHaxiomInterface(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomInterface) || (Reflect.hasField(val, "name") && Reflect.hasField(val, "methods")
			&& Reflect.hasField(val, "parents") && !Reflect.hasField(val, "staticFields")));
	}

	static function isHaxiomEnum(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomEnum) || (Reflect.hasField(val, "name") && Reflect.hasField(val, "constructors")
			&& Reflect.hasField(val, "params")));
	}

	static function isHaxiomAbstract(val:Dynamic):Bool {
		return val != null && (Std.isOfType(val, HaxiomAbstract) || (Reflect.hasField(val, "name") && Reflect.hasField(val, "underlyingType")
			&& Reflect.hasField(val, "staticFields")));
	}

	static function isString(v:Dynamic):Bool {
		if (v == null)
			return false;
		var t = Type.typeof(v);
		switch (t) {
			case TClass(c):
				return c == String || Type.getClassName(c) == "String";
			default:
				return false;
		}
	}

	static function isInt(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Int))
			return true;
		var t = Type.typeof(v);
		switch (t) {
			case TInt:
				return true;
			default:
		}
		if (isString(v)) {
			return ~/^-?[0-9]+$/.match(cast v);
		}
		return false;
	}

	static function isFloat(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Float))
			return true;
		var t = Type.typeof(v);
		switch (t) {
			case TInt | TFloat:
				return true;
			default:
		}
		if (isString(v)) {
			return ~/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.match(cast v);
		}
		return false;
	}

	static function isBool(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Bool))
			return true;
		var t = Type.typeof(v);
		switch (t) {
			case TBool:
				return true;
			default:
				return false;
		}
	}

	static function checkType(interp:Interp, val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Void {
		castOrCheckType(interp, val, type, scope, genericBindings);
	}

	static function castOrCheckType(interp:Interp, val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Dynamic {
		if (type == null)
			return val;
		var resolvedType = interp.resolveGenericType(type, genericBindings, scope);
		resolvedType = interp.resolveType(resolvedType, scope);

		switch (resolvedType) {
			case TPath(path, params):
				var typeName = path.join(".");

				var resolvedTypePathVal:Dynamic = interp.resolveTypePath(path, scope);
				var isGuestType = isHaxiomGuestType(resolvedTypePathVal);

				if (!isGuestType) {
					switch (typeName) {
						case "Dynamic": return val;
						case "Void":
							if (val != null)
								throw "Type mismatch: expected Void";
							return val;
						case "Int" | "std.Int":
							if (Std.isOfType(val, HaxiomAbstractInstance)) {
								var inst:HaxiomAbstractInstance = cast val;
								if (canAbstractCastTo(inst.abstractType, "Int", interp, scope)) {
									var casted = callToMethod(inst, "Int", interp, scope);
									if (casted != null)
										return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
									return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
								}
							}
							if (!isInt(val)) {
								var valClass = Type.getClass(val);
								var valClassName = valClass != null ? Type.getClassName(valClass) : null;
								throw 'Type mismatch: expected Int but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
							}
							return val;
						case "Float" | "std.Float":
							if (Std.isOfType(val, HaxiomAbstractInstance)) {
								var inst:HaxiomAbstractInstance = cast val;
								if (canAbstractCastTo(inst.abstractType, "Float", interp, scope)) {
									var casted = callToMethod(inst, "Float", interp, scope);
									if (casted != null)
										return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
									return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
								}
							}
							if (!isFloat(val))
								throw 'Type mismatch: expected Float but got ${val == null ? "null" : Std.string(val)}';
							return val;
						case "String" | "std.String":
							if (Std.isOfType(val, HaxiomAbstractInstance)) {
								var inst:HaxiomAbstractInstance = cast val;
								if (canAbstractCastTo(inst.abstractType, "String", interp, scope)) {
									var casted = callToMethod(inst, "String", interp, scope);
									if (casted != null)
										return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
									return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
								}
							}
							if (!isString(val))
								throw 'Type mismatch: expected String but got ${val == null ? "null" : Std.string(val)}';
							return val;
						case "Bool" | "std.Bool":
							if (Std.isOfType(val, HaxiomAbstractInstance)) {
								var inst:HaxiomAbstractInstance = cast val;
								if (canAbstractCastTo(inst.abstractType, "Bool", interp, scope)) {
									var casted = callToMethod(inst, "Bool", interp, scope);
									if (casted != null)
										return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
									return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
								}
							}
							if (!isBool(val))
								throw 'Type mismatch: expected Bool but got ${val == null ? "null" : Std.string(val)}';
							return val;
						case "Array" | "std.Array":
							if (val == null)
								return null;
							if (!Std.isOfType(val, Array))
								throw 'Type mismatch: expected Array but got ${val == null ? "null" : Std.string(val)}';
							if (params != null && params.length > 0) {
								var arr:Array<Dynamic> = cast val;
								for (i in 0...arr.length) {
									arr[i] = castOrCheckType(interp, arr[i], params[0], scope, genericBindings);
								}
							}
							return val;
						case "List" | "haxe.ds.List":
							if (val == null)
								return null;
							if (!Std.isOfType(val, haxe.ds.List))
								throw 'Type mismatch: expected List but got ${val == null ? "null" : Std.string(val)}';
							if (params != null && params.length > 0) {
								var list:haxe.ds.List<Dynamic> = cast val;
								var temp = [];
								var changed = false;
								for (item in list) {
									var coerced = castOrCheckType(interp, item, params[0], scope, genericBindings);
									if (coerced != item)
										changed = true;
									temp.push(coerced);
								}
								if (changed) {
									list.clear();
									for (item in temp)
										list.add(item);
								}
							}
							return val;
						case "Map" | "haxe.ds.Map":
							if (val == null)
								return null;
							if (!Std.isOfType(val, haxe.Constraints.IMap))
								throw 'Type mismatch: expected Map but got ${val == null ? "null" : Std.string(val)}';
							if (params != null && params.length > 1) {
								var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast val;
								for (key in map.keys()) {
									var coercedKey = castOrCheckType(interp, key, params[0], scope, genericBindings);
									var coercedVal = castOrCheckType(interp, map.get(key), params[1], scope, genericBindings);
									if (coercedKey != key) {
										map.remove(key);
										map.set(coercedKey, coercedVal);
									} else {
										map.set(key, coercedVal);
									}
								}
							}
							return val;
						default:
							// Fall through to check custom scope types
					}
				}

				var cls:Dynamic = resolvedTypePathVal;
				if (cls == null && scope.exists(typeName))
					cls = scope.get(typeName);
				if (cls == null && interp.globals != null)
					cls = interp.globals.get(typeName);
				if (cls == null && interp.globals != null && interp.globals.types != null && interp.globals.types.exists(typeName))
					cls = interp.globals.types.get(typeName);

				if (cls != null) {
					if (isHaxiomAbstract(cls)) {
						var abs:HaxiomAbstract = cast cls;
						if (val == null)
							return null;

						if (isHaxiomAbstractInstance(val)) {
							var inst:HaxiomAbstractInstance = cast val;
							if (inst.abstractType == abs || (inst.abstractType != null && abs != null && inst.abstractType.name == abs.name))
								return val;
						}

						var fromMethod = findFromMethod(abs, val, interp, scope);
						if (fromMethod != null) {
							var bound = interp.bindMethod(abs, fromMethod);
							return Reflect.callMethod(null, bound, [val]);
						}

						if (canAbstractCastFrom(abs, val, interp, scope)) {
							return new HaxiomAbstractInstance(abs, val);
						}

						throw 'Type mismatch: expected abstract $typeName but got ${val == null ? "null" : Std.string(val)}';
					}

					if (isHaxiomClass(cls)) {
						if (val == null)
							return null;
						var isHaxInst = isHaxiomInstance(val);
						var valClass = Type.getClass(val);
						var valClassName = valClass != null ? Type.getClassName(valClass) : "null";
						if (!isHaxInst)
							throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
						var targetClass:HaxiomClass = cast cls;
						var instCls:HaxiomClass = cast Reflect.field(val, "cls");
						var curr:HaxiomClass = instCls;
						var isSub = false;
						while (curr != null) {
							if (curr == targetClass || (curr != null && targetClass != null && curr.name == targetClass.name)) {
								isSub = true;
								break;
							}
							curr = curr.parent;
						}
						if (!isSub) {
							var instClsName:String = instCls != null ? instCls.name : "unknown";
							throw 'Type mismatch: expected $typeName but got $instClsName';
						}
						if (params != null && params.length > 0 && targetClass.params != null) {
							var genericBindingsVal:Map<String, TypeDecl> = cast Reflect.field(val, "genericBindings");
							if (genericBindingsVal != null) {
								for (i in 0...Std.int(Math.min(params.length, targetClass.params.length))) {
									var expectedParam = params[i];
									var pName:String = targetClass.params[i].name;
									var actualParam = genericBindingsVal.get(targetClass.name + "." + pName);
									if (actualParam != null && !interp.typesEqual(actualParam, expectedParam)) {
										throw 'Type mismatch: expected type parameter ${pName} to be ${interp.typeToString(expectedParam)} but got ${interp.typeToString(actualParam)}';
									}
								}
							}
						}
						return val;
					}

					if (isHaxiomInterface(cls)) {
						if (val == null)
							return null;
						if (!isHaxiomInstance(val))
							throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
						var inst:HaxiomInstance = cast val;
						var itf:HaxiomInterface = cast cls;
						var curr:HaxiomClass = inst.cls;
						var matchedItf:TypeDecl = null;
						while (curr != null) {
							if (curr.interfaces != null) {
								for (itfDecl in curr.interfaces) {
									switch (itfDecl) {
										case TPath(itfPath, _):
											var curItfName = itfPath.join(".");
											if (interp.isInterfaceCompatible(curItfName, itf.name, scope)) {
												matchedItf = itfDecl;
												break;
											}
										default:
									}
								}
							}
							if (matchedItf != null)
								break;
							curr = curr.parent;
						}
						if (matchedItf == null) {
							var instClsName:String = (inst != null && inst.cls != null) ? inst.cls.name : "unknown";
							throw 'Type mismatch: expected interface $typeName but got $instClsName';
						}
						if (params != null && params.length > 0 && itf.params != null) {
							if (inst.genericBindings != null) {
								for (i in 0...Std.int(Math.min(params.length, itf.params.length))) {
									var expectedParam = params[i];
									var pName:String = itf.params[i].name;
									var actualParam = inst.genericBindings.get(itf.name + "." + pName);
									if (actualParam != null && !interp.typesEqual(actualParam, expectedParam)) {
										throw 'Type mismatch: expected interface type parameter ${pName} to be ${interp.typeToString(expectedParam)} but got ${interp.typeToString(actualParam)}';
									}
								}
							}
						}
						return val;
					}

					if (isHaxiomEnum(cls)) {
						if (val == null)
							return null;
						if (!isHaxiomEnumInstance(val))
							throw 'Type mismatch: expected $typeName';
						var inst:HaxiomEnumInstance = cast val;
						var enumCls:HaxiomEnum = cast cls;
						if (inst.enumType == enumCls || (inst.enumType != null && enumCls != null && inst.enumType.name == enumCls.name))
							return val;
						throw 'Type mismatch: expected enum $typeName but got ${inst.enumType.name}';
					}
				}

				// Fall back to original native type/class lookup
				var resolvedTypePathVal = interp.resolveTypePath(path, scope);
				var fqAbstractName:String = null;
				var exposedAbs = interp != null ? interp.ffi.exposedAbstracts : null;
				if (fqAbstractName == null && exposedAbs != null) {
					if (exposedAbs.exists(typeName)) {
						fqAbstractName = typeName;
					} else {
						for (k in exposedAbs.keys()) {
							var shortName = k.split(".").pop();
							if (shortName == typeName) {
								fqAbstractName = k;
								break;
							}
						}
					}
					if (fqAbstractName == null && resolvedTypePathVal != null) {
						var resolvedClassName = interp.safeGetClassName(resolvedTypePathVal);
						if (resolvedClassName != null) {
							for (k in exposedAbs.keys()) {
								if (exposedAbs.get(k).implClass == resolvedClassName) {
									fqAbstractName = k;
									break;
								}
							}
						}
					}
				}

				if (fqAbstractName != null && exposedAbs != null) {
					var absInfo = exposedAbs.get(fqAbstractName);
					var underlyingTypeDecl = TPath(absInfo.underlying.split("."), []);
					return castOrCheckType(interp, val, underlyingTypeDecl, scope, genericBindings);
				}

				var nativeClass:Dynamic = null;
				if (resolvedTypePathVal != null) {
					if (!isHaxiomGuestType(resolvedTypePathVal)) {
						nativeClass = resolvedTypePathVal;
					}
				}
				if (nativeClass == null) {
					nativeClass = interp.resolveNativeClass(typeName);
				}
				if (nativeClass != null) {
					if (val == null)
						return null;
					#if cpp
					var valClass = Type.getClass(val);
					if (valClass != null) {
						var valClassName = Type.getClassName(valClass);
						var targetClassName = Type.getClassName(nativeClass);
						if (valClassName == targetClassName || Std.isOfType(val, nativeClass)) {
							return val;
						}
						var currClass:Class<Dynamic> = valClass;
						while (currClass != null) {
							if (Type.getClassName(currClass) == targetClassName)
								return val;
							currClass = Type.getSuperClass(currClass);
						}
					}
					#end

					var isMatch = false;
					var nName = nativeClass != null ? Type.getClassName(nativeClass) : null;
					if (nName == "String") {
						isMatch = isString(val);
					} else if (nName == "Int") {
						isMatch = isInt(val);
					} else if (nName == "Float") {
						isMatch = isFloat(val);
					} else if (nName == "Bool") {
						isMatch = isBool(val);
					} else {
						isMatch = Std.isOfType(val, nativeClass);
					}

					if (!isMatch) {
						var valClass = Type.getClass(val);
						var valClassName = valClass != null ? Type.getClassName(valClass) : null;
						throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
					}
					return val;
				}

				var valClass = Type.getClass(val);
				if (valClass != null) {
					var valClassName = Type.getClassName(valClass);
					if (valClassName == typeName)
						return val;
				}

				throw 'Type mismatch: expected $typeName';
			case TFun(args, ret):
				if (!Reflect.isFunction(val))
					throw "Type mismatch: expected Function";
				if (interp.functionSignatures.exists(val)) {
					var actualSig = interp.functionSignatures.get(val);
					switch (actualSig) {
						case TFun(actualArgs, actualRet):
							if (actualArgs.length != args.length) {
								throw 'Type mismatch: expected function with ${args.length} arguments but got ${actualArgs.length}';
							}
							for (i in 0...args.length) {
								var expectedArgResolved = interp.resolveType(args[i], scope);
								var actualArgResolved = interp.resolveType(actualArgs[i], scope);
								if (!interp.typesEqual(expectedArgResolved, actualArgResolved)) {
									throw 'Type mismatch in function argument ${i + 1}: expected ${interp.typeToString(args[i])} but got ${interp.typeToString(actualArgs[i])}';
								}
							}
							var expectedRetResolved = interp.resolveType(ret, scope);
							var actualRetResolved = interp.resolveType(actualRet, scope);
							if (!interp.typesEqual(expectedRetResolved, actualRetResolved)) {
								throw 'Type mismatch in function return type: expected ${interp.typeToString(ret)} but got ${interp.typeToString(actualRet)}';
							}
						default:
					}
				}
				return val;
			case TAnonymous(fields):
				if (val == null)
					return null;
				if (Reflect.isFunction(val) || Std.isOfType(val, Int) || Std.isOfType(val, Float) || Std.isOfType(val, Bool) || Std.isOfType(val, String)) {
					throw 'Type mismatch: expected anonymous structure but got ' + interp.getTypeName(val);
				}
				for (field in fields) {
					var res = interp.hasAndGetField(val, field.name);
					if (!res.exists) {
						if (field.opt)
							continue;
						throw 'Type mismatch: object is missing field "${field.name}"';
					}
					try {
						var coercedVal = castOrCheckType(interp, res.val, field.type, scope, genericBindings);
						if (coercedVal != res.val) {
							Reflect.setField(val, field.name, coercedVal);
						}
					} catch (e:Dynamic) {
						throw 'Type mismatch in field "${field.name}": ' + Std.string(e);
					}
				}
				return val;
		}
	}

	static function hasMeta(meta:Array<{name:String, params:Array<Dynamic>}>, name:String):Bool {
		if (meta == null)
			return false;
		for (m in meta) {
			if (m.name == name || m.name == ":" + name)
				return true;
		}
		return false;
	}

	static function findFromMethod(abs:HaxiomAbstract, val:Dynamic, interp:Interp, scope:Scope):Null<Dynamic> {
		for (m in abs.methods) {
			if (m.isStatic && (hasMeta(m.meta, "from") || hasMeta(m.meta, ":from"))) {
				if (m.args.length == 1) {
					try {
						checkType(interp, val, m.args[0].type, scope);
						return m;
					} catch (_:Dynamic) {}
				}
			}
		}
		return null;
	}

	static function findToMethod(abs:HaxiomAbstract, targetTypeName:String, interp:Interp, scope:Scope):Null<Dynamic> {
		for (m in abs.methods) {
			if (!m.isStatic && (hasMeta(m.meta, "to") || hasMeta(m.meta, ":to"))) {
				if (m.retType != null) {
					var retTypeName = interp.typeToString(m.retType);
					if (retTypeName == targetTypeName) {
						return m;
					}
				}
			}
		}
		return null;
	}

	static function callToMethod(inst:HaxiomAbstractInstance, targetTypeName:String, interp:Interp, scope:Scope):Dynamic {
		var toMethod = findToMethod(inst.abstractType, targetTypeName, interp, scope);
		if (toMethod != null) {
			var bound = interp.bindMethod(inst, toMethod);
			return Reflect.callMethod(null, bound, []);
		}
		return null;
	}

	static function canAbstractCastFrom(abs:HaxiomAbstract, val:Dynamic, interp:Interp, scope:Scope):Bool {
		try {
			checkType(interp, val, abs.underlyingType, scope);
			return true;
		} catch (_:Dynamic) {}

		for (fTypeStr in abs.fromTypes) {
			try {
				var fType = parseTypeString(fTypeStr);
				checkType(interp, val, fType, scope);
				return true;
			} catch (_:Dynamic) {}
		}
		return false;
	}

	static function canAbstractCastTo(abs:HaxiomAbstract, targetTypeName:String, interp:Interp, scope:Scope):Bool {
		var underlyingTypeName = interp.typeToString(abs.underlyingType);
		if (underlyingTypeName == targetTypeName)
			return true;

		var toMethod = findToMethod(abs, targetTypeName, interp, scope);
		if (toMethod != null)
			return true;

		for (tTypeStr in abs.toTypes) {
			if (tTypeStr == targetTypeName)
				return true;
		}

		return false;
	}

	static function parseTypeString(str:String):TypeDecl {
		var lexer = new haxiom.Lexer(str, "type_string");
		var tokens = lexer.tokenize();
		var parser = new haxiom.Parser(tokens, "type_string");
		return parser.parseType();
	}
}
