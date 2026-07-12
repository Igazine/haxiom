package haxiom;

import haxiom.AST.TypeDecl;
import haxiom.Interp.Scope;
import haxiom.Interp.HaxiomClass;
import haxiom.Interp.HaxiomInstance;
import haxiom.Interp.HaxiomInterface;
import haxiom.Interp.HaxiomEnum;
import haxiom.Interp.HaxiomEnumInstance;
import haxiom.Interp.HaxiomAbstract;
import haxiom.Interp.HaxiomAbstractInstance;

class TypeSystem {
    public static function isString(v:Dynamic):Bool {
        if (v == null) return false;
        var isOf = Std.isOfType(v, String);
        var t = Type.typeof(v);
        var isCls = false;
        switch (t) {
            case TClass(c):
                isCls = (c == String || Type.getClassName(c) == "String");
            default:
        }
        #if haxiom_debug
        trace("DEBUG isString val=" + Std.string(v) + " isOf=" + isOf + " type=" + Std.string(t) + " isCls=" + isCls);
        #end
        return isOf || isCls;
    }

    public static function isInt(v:Dynamic):Bool {
        if (v == null) return false;
        #if haxiom_debug
        trace("DEBUG isInt val=" + Std.string(v) + " typeof=" + Std.string(Type.typeof(v)) + " isOfType=" + Std.isOfType(v, Int));
        #end
        if (Std.isOfType(v, Int)) return true;
        var t = Type.typeof(v);
        switch (t) {
            case TInt: return true;
            default:
        }
        if (isString(v)) {
            return ~/^-?[0-9]+$/.match(cast v);
        }
        return false;
    }

    public static function isFloat(v:Dynamic):Bool {
        if (v == null) return false;
        if (Std.isOfType(v, Float)) return true;
        var t = Type.typeof(v);
        switch (t) {
            case TInt | TFloat: return true;
            default:
        }
        if (isString(v)) {
            return ~/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.match(cast v);
        }
        return false;
    }

    public static function isBool(v:Dynamic):Bool {
        if (v == null) return false;
        if (Std.isOfType(v, Bool)) return true;
        var t = Type.typeof(v);
        switch (t) {
            case TBool: return true;
            default: return false;
        }
    }

    public static function checkType(interp:Interp, val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Void {
        castOrCheckType(interp, val, type, scope, genericBindings);
    }

    public static function castOrCheckType(interp:Interp, val:Dynamic, type:TypeDecl, scope:Scope, ?genericBindings:Map<String, TypeDecl>):Dynamic {
        if (type == null) return val;
        var resolvedType = interp.resolveGenericType(type, genericBindings, scope);
        resolvedType = interp.resolveType(resolvedType, scope);
        
        switch (resolvedType) {
            case TPath(path, params):
                var typeName = path.join(".");
                
                var resolvedTypePathVal = interp.resolveTypePath(path, scope);
                var isGuestType = false;
                if (resolvedTypePathVal != null) {
                    if (Std.isOfType(resolvedTypePathVal, haxiom.Interp.HaxiomClass) ||
                        Std.isOfType(resolvedTypePathVal, haxiom.Interp.HaxiomInterface) ||
                        Std.isOfType(resolvedTypePathVal, haxiom.Interp.HaxiomEnum) ||
                        Std.isOfType(resolvedTypePathVal, haxiom.Interp.HaxiomAbstract)) {
                        isGuestType = true;
                    }
                }
                
                if (!isGuestType) {
                    switch (typeName) {
                        case "Dynamic": return val;
                        case "Void":
                            if (val != null) throw "Type mismatch: expected Void";
                            return val;
                        case "Int":
                            if (Std.isOfType(val, HaxiomAbstractInstance)) {
                                var inst:HaxiomAbstractInstance = cast val;
                                if (canAbstractCastTo(inst.abstractType, "Int", interp, scope)) {
                                    var casted = callToMethod(inst, "Int", interp, scope);
                                    if (casted != null) return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
                                    return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
                                }
                            }
                            if (!isInt(val)) {
                                var valClass = Type.getClass(val);
                                var valClassName = valClass != null ? Type.getClassName(valClass) : null;
                                throw 'Type mismatch: expected Int but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
                            }
                            return val;
                        case "Float":
                            if (Std.isOfType(val, HaxiomAbstractInstance)) {
                                var inst:HaxiomAbstractInstance = cast val;
                                if (canAbstractCastTo(inst.abstractType, "Float", interp, scope)) {
                                    var casted = callToMethod(inst, "Float", interp, scope);
                                    if (casted != null) return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
                                    return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
                                }
                            }
                            if (!isFloat(val)) throw 'Type mismatch: expected Float but got ${val == null ? "null" : Std.string(val)}';
                            return val;
                        case "String":
                            if (Std.isOfType(val, HaxiomAbstractInstance)) {
                                var inst:HaxiomAbstractInstance = cast val;
                                if (canAbstractCastTo(inst.abstractType, "String", interp, scope)) {
                                    var casted = callToMethod(inst, "String", interp, scope);
                                    if (casted != null) return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
                                    return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
                                }
                            }
                            if (!isString(val)) throw 'Type mismatch: expected String but got ${val == null ? "null" : Std.string(val)}';
                            return val;
                        case "Bool":
                            if (Std.isOfType(val, HaxiomAbstractInstance)) {
                                var inst:HaxiomAbstractInstance = cast val;
                                if (canAbstractCastTo(inst.abstractType, "Bool", interp, scope)) {
                                    var casted = callToMethod(inst, "Bool", interp, scope);
                                    if (casted != null) return castOrCheckType(interp, casted, resolvedType, scope, genericBindings);
                                    return castOrCheckType(interp, inst.underlyingValue, resolvedType, scope, genericBindings);
                                }
                            }
                            if (!isBool(val)) throw 'Type mismatch: expected Bool but got ${val == null ? "null" : Std.string(val)}';
                            return val;
                        case "Array":
                            if (val == null) return null;
                            if (!Std.isOfType(val, Array)) throw 'Type mismatch: expected Array but got ${val == null ? "null" : Std.string(val)}';
                            if (params != null && params.length > 0) {
                                var arr:Array<Dynamic> = cast val;
                                for (i in 0...arr.length) {
                                    arr[i] = castOrCheckType(interp, arr[i], params[0], scope, genericBindings);
                                }
                            }
                            return val;
                        case "List" | "haxe.ds.List":
                            if (val == null) return null;
                            if (!Std.isOfType(val, haxe.ds.List)) throw 'Type mismatch: expected List but got ${val == null ? "null" : Std.string(val)}';
                            if (params != null && params.length > 0) {
                                var list:haxe.ds.List<Dynamic> = cast val;
                                var temp = [];
                                var changed = false;
                                for (item in list) {
                                    var coerced = castOrCheckType(interp, item, params[0], scope, genericBindings);
                                    if (coerced != item) changed = true;
                                    temp.push(coerced);
                                }
                                if (changed) {
                                    list.clear();
                                    for (item in temp) list.add(item);
                                }
                            }
                            return val;
                        case "Map" | "haxe.ds.Map":
                            if (val == null) return null;
                            if (!Std.isOfType(val, haxe.Constraints.IMap)) throw 'Type mismatch: expected Map but got ${val == null ? "null" : Std.string(val)}';
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
                
                var cls = resolvedTypePathVal;
                if (cls == null && scope.exists(typeName)) {
                    cls = scope.get(typeName);
                }
                
                if (cls != null) {
                    if (Std.isOfType(cls, haxiom.Interp.HaxiomAbstract)) {
                        var abs:HaxiomAbstract = cast cls;
                        if (val == null) return null;
                        
                        if (Std.isOfType(val, HaxiomAbstractInstance)) {
                            var inst:HaxiomAbstractInstance = cast val;
                            if (inst.abstractType == abs) return val;
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
                    
                    if (Std.isOfType(cls, haxiom.Interp.HaxiomClass)) {
                        if (val == null) return null;
                        if (!Std.isOfType(val, HaxiomInstance)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                        var inst:HaxiomInstance = cast val;
                        var curr = inst.cls;
                        var isSub = false;
                        while (curr != null) {
                            if (curr == cls) {
                                isSub = true;
                                break;
                            }
                            curr = curr.parent;
                        }
                        if (!isSub) throw 'Type mismatch: expected $typeName but got ${inst.cls.name}';
                        if (params != null && params.length > 0 && cls.params != null) {
                            for (i in 0...Std.int(Math.min(params.length, cls.params.length))) {
                                var expectedParam = params[i];
                                var actualParam = inst.genericBindings.get(cls.name + "." + cls.params[i]);
                                if (actualParam != null && !interp.typesEqual(actualParam, expectedParam)) {
                                    throw 'Type mismatch: expected type parameter ${cls.params[i]} to be ${interp.typeToString(expectedParam)} but got ${interp.typeToString(actualParam)}';
                                }
                            }
                        }
                        return val;
                    }
                    
                    if (Std.isOfType(cls, haxiom.Interp.HaxiomInterface)) {
                        if (val == null) return null;
                        if (!Std.isOfType(val, HaxiomInstance)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                        var inst:HaxiomInstance = cast val;
                        var itf:HaxiomInterface = cast cls;
                        var curr = inst.cls;
                        var matchedItf:TypeDecl = null;
                        while (curr != null) {
                            for (itfDecl in curr.interfaces) {
                                switch (itfDecl) {
                                    case TPath(itfPath, _):
                                        var itfName = itfPath.join(".");
                                        if (interp.isInterfaceCompatible(itfName, itf.name, scope)) {
                                            matchedItf = itfDecl;
                                            break;
                                        }
                                    default:
                                }
                            }
                            if (matchedItf != null) break;
                            curr = curr.parent;
                        }
                        if (matchedItf == null) {
                            throw 'Type mismatch: expected interface $typeName but got ${inst.cls.name}';
                        }
                        if (params != null && params.length > 0 && itf.params != null) {
                            for (i in 0...Std.int(Math.min(params.length, itf.params.length))) {
                                var expectedParam = params[i];
                                var actualParam = inst.genericBindings.get(itf.name + "." + itf.params[i]);
                                if (actualParam != null && !interp.typesEqual(actualParam, expectedParam)) {
                                    throw 'Type mismatch: expected interface type parameter ${itf.params[i]} to be ${interp.typeToString(expectedParam)} but got ${interp.typeToString(actualParam)}';
                                }
                            }
                        }
                        return val;
                    }
                    
                    if (Std.isOfType(cls, haxiom.Interp.HaxiomEnum)) {
                        if (val == null) return null;
                        if (!Std.isOfType(val, HaxiomEnumInstance)) throw 'Type mismatch: expected $typeName';
                        var inst:HaxiomEnumInstance = cast val;
                        var enumCls:HaxiomEnum = cast cls;
                        if (inst.enumType == enumCls) return val;
                        throw 'Type mismatch: expected enum $typeName but got ${inst.enumType.name}';
                    }
                }
                
                // Fall back to original native type/class lookup
                var resolvedTypePathVal = interp.resolveTypePath(path, scope);
                        var fqAbstractName:String = null;
                        if (fqAbstractName == null) {
                            if (haxiom.FFI.exposedAbstracts.exists(typeName)) {
                                fqAbstractName = typeName;
                            } else if (resolvedTypePathVal != null) {
                                var resolvedClassName = interp.safeGetClassName(resolvedTypePathVal);
                                if (resolvedClassName != null) {
                                    for (k in haxiom.FFI.exposedAbstracts.keys()) {
                                        if (haxiom.FFI.exposedAbstracts.get(k).implClass == resolvedClassName) {
                                            fqAbstractName = k;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        
                        if (fqAbstractName != null) {
                            var absInfo = haxiom.FFI.exposedAbstracts.get(fqAbstractName);
                            var underlyingTypeDecl = TPath(absInfo.underlying.split("."), []);
                            return castOrCheckType(interp, val, underlyingTypeDecl, scope, genericBindings);
                        }

                        var nativeClass:Dynamic = null;
                        if (resolvedTypePathVal != null) {
                            if (!Std.isOfType(resolvedTypePathVal, HaxiomClass) && 
                                !Std.isOfType(resolvedTypePathVal, HaxiomInterface) && 
                                !Std.isOfType(resolvedTypePathVal, HaxiomEnum) && 
                                !Std.isOfType(resolvedTypePathVal, HaxiomAbstract)) {
                                nativeClass = resolvedTypePathVal;
                            }
                        }
                        if (nativeClass == null) {
                            nativeClass = interp.resolveNativeClass(typeName);
                        }
                        if (nativeClass != null) {
                            if (val == null) return null;
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
                                    if (Type.getClassName(currClass) == targetClassName) return val;
                                    currClass = Type.getSuperClass(currClass);
                                }
                            }
                            #end

                            if (!Std.isOfType(val, nativeClass)) {
                                var valClass = Type.getClass(val);
                                var valClassName = valClass != null ? Type.getClassName(valClass) : null;
                                throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
                            }
                            return val;
                        }
                        
                        var valClass = Type.getClass(val);
                        if (valClass != null) {
                            var valClassName = Type.getClassName(valClass);
                            if (valClassName == typeName) return val;
                        }

                        throw 'Type mismatch: expected $typeName';
            case TFun(args, ret):
                if (!Reflect.isFunction(val)) throw "Type mismatch: expected Function";
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
                if (val == null) return null;
                if (Reflect.isFunction(val) || Std.isOfType(val, Int) || Std.isOfType(val, Float) || Std.isOfType(val, Bool) || Std.isOfType(val, String)) {
                    throw 'Type mismatch: expected anonymous structure but got ' + interp.getTypeName(val);
                }
                for (field in fields) {
                    var res = interp.hasAndGetField(val, field.name);
                    if (!res.exists) {
                        if (field.opt) continue;
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
        if (meta == null) return false;
        for (m in meta) {
            if (m.name == name || m.name == ":" + name) return true;
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

    public static function canAbstractCastFrom(abs:HaxiomAbstract, val:Dynamic, interp:Interp, scope:Scope):Bool {
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

    public static function canAbstractCastTo(abs:HaxiomAbstract, targetTypeName:String, interp:Interp, scope:Scope):Bool {
        var underlyingTypeName = interp.typeToString(abs.underlyingType);
        if (underlyingTypeName == targetTypeName) return true;

        var toMethod = findToMethod(abs, targetTypeName, interp, scope);
        if (toMethod != null) return true;
        
        for (tTypeStr in abs.toTypes) {
            if (tTypeStr == targetTypeName) return true;
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
