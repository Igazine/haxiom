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
        if (type == null) return;
        var resolvedType = interp.resolveGenericType(type, genericBindings, scope);
        resolvedType = interp.resolveType(resolvedType, scope);
        
        switch (resolvedType) {
            case TPath(path, params):
                var typeName = path.join(".");
                switch (typeName) {
                    case "Dynamic": return;
                    case "Void":
                        if (val != null) throw "Type mismatch: expected Void";
                    case "Int":
                        if (!isInt(val)) {
                            var valClass = Type.getClass(val);
                            var valClassName = valClass != null ? Type.getClassName(valClass) : null;
                            throw 'Type mismatch: expected Int but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
                        }
                    case "Float":
                        if (!isFloat(val)) throw 'Type mismatch: expected Float but got ${val == null ? "null" : Std.string(val)}';
                    case "String":
                        if (!isString(val)) throw 'Type mismatch: expected String but got ${val == null ? "null" : Std.string(val)}';
                    case "Bool":
                        if (!isBool(val)) throw 'Type mismatch: expected Bool but got ${val == null ? "null" : Std.string(val)}';
                    case "Array":
                        if (val == null) return;
                        if (!Std.isOfType(val, Array)) throw 'Type mismatch: expected Array but got ${val == null ? "null" : Std.string(val)}';
                        if (params != null && params.length > 0) {
                            var arr:Array<Dynamic> = cast val;
                            for (item in arr) {
                                checkType(interp, item, params[0], scope, genericBindings);
                            }
                        }
                    case "List" | "haxe.ds.List":
                        if (val == null) return;
                        if (!Std.isOfType(val, haxe.ds.List)) throw 'Type mismatch: expected List but got ${val == null ? "null" : Std.string(val)}';
                        if (params != null && params.length > 0) {
                            var list:haxe.ds.List<Dynamic> = cast val;
                            for (item in list) {
                                checkType(interp, item, params[0], scope, genericBindings);
                            }
                        }
                    case "Map" | "haxe.ds.Map":
                        if (val == null) return;
                        if (!Std.isOfType(val, haxe.Constraints.IMap)) throw 'Type mismatch: expected Map but got ${val == null ? "null" : Std.string(val)}';
                        if (params != null && params.length > 1) {
                            var map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast val;
                            for (key in map.keys()) {
                                checkType(interp, key, params[0], scope, genericBindings);
                                checkType(interp, map.get(key), params[1], scope, genericBindings);
                            }
                        }
                    default:
                        // 1. Check if typeName is a Haxiom-defined class
                        if (scope.exists(typeName)) {
                            var cls = scope.get(typeName);
                            if (Std.isOfType(cls, HaxiomClass)) {
                                if (val == null) return;
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
                                return;
                            }
                            if (Std.isOfType(cls, HaxiomInterface)) {
                                if (val == null) return;
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
                                return;
                            }
                            if (Std.isOfType(cls, HaxiomEnum)) {
                                if (val == null) return;
                                if (!Std.isOfType(val, HaxiomEnumInstance)) throw 'Type mismatch: expected $typeName';
                                var inst:HaxiomEnumInstance = cast val;
                                var enumCls:HaxiomEnum = cast cls;
                                if (inst.enumType == enumCls) return;
                                throw 'Type mismatch: expected enum $typeName but got ${inst.enumType.name}';
                            }
                            if (Std.isOfType(cls, HaxiomAbstract)) {
                                if (val == null) return;
                                if (!Std.isOfType(val, HaxiomAbstractInstance)) throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : Std.string(val)}';
                                var inst:HaxiomAbstractInstance = cast val;
                                var abs:HaxiomAbstract = cast cls;
                                if (inst.abstractType == abs) return;
                                throw 'Type mismatch: expected abstract $typeName but got ${inst.abstractType.name}';
                            }
                        }
                        
                        // 2. Check FFI registered abstract / native type checks
                        var resolvedTypePathVal = interp.resolveTypePath(path, scope);
                        var fqAbstractName:String = null;
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
                        
                        if (fqAbstractName != null) {
                            var absInfo = haxiom.FFI.exposedAbstracts.get(fqAbstractName);
                            var underlyingTypeDecl = TPath(absInfo.underlying.split("."), []);
                            checkType(interp, val, underlyingTypeDecl, scope, genericBindings);
                            return;
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
                            #if haxiom_debug
                            trace('checkType: typeName=' + typeName + ' nativeClass=' + nativeClass + ' val=' + Std.string(val) + ' isOfType=' + Std.isOfType(val, nativeClass));
                            #end
                            if (val == null) return;
                            
                            #if cpp
                            var valClass = Type.getClass(val);
                            if (valClass != null) {
                                var valClassName = Type.getClassName(valClass);
                                var targetClassName = Type.getClassName(nativeClass);
                                if (valClassName == targetClassName || Std.isOfType(val, nativeClass)) {
                                    return;
                                }
                                var currClass:Class<Dynamic> = valClass;
                                while (currClass != null) {
                                    if (Type.getClassName(currClass) == targetClassName) return;
                                    currClass = Type.getSuperClass(currClass);
                                }
                            }
                            #end

                            if (!Std.isOfType(val, nativeClass)) {
                                var valClass = Type.getClass(val);
                                var valClassName = valClass != null ? Type.getClassName(valClass) : null;
                                throw 'Type mismatch: expected $typeName but got ${val == null ? "null" : valClassName != null ? valClassName : Std.string(val)}';
                            }
                            return;
                        }
                        
                        var valClass = Type.getClass(val);
                        if (valClass != null) {
                            var valClassName = Type.getClassName(valClass);
                            if (valClassName == typeName) return;
                        }

                        throw 'Type mismatch: expected $typeName';
                }
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
            case TAnonymous(fields):
                if (val == null) return;
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
                        checkType(interp, res.val, field.type, scope, genericBindings);
                    } catch (e:Dynamic) {
                        throw 'Type mismatch in field "${field.name}": ' + Std.string(e);
                    }
                }
        }
    }
}
