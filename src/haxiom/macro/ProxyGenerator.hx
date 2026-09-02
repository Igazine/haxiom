package haxiom.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

@:allow(haxiom.Haxiom)
class ProxyGenerator {
    static var definedProxies:Map<String, Bool> = new Map();

    static function boundaryType(type:Type, pos:Position, ?nullable:Bool = false):Expr {
        switch (type) {
            case TAbstract(ref, params):
                var abstractType = ref.get();
                var name = abstractType.pack.concat([abstractType.name]).join(".");
                if (name == "Null" && params.length == 1)
                    return boundaryType(params[0], pos, true);
            default:
        }

        return switch (Context.follow(type)) {
            case TAbstract(ref, _):
                var abstractType = ref.get();
                var name = abstractType.pack.concat([abstractType.name]).join(".");
                var kind = switch (name) {
                    case "Bool": "bool";
                    case "Int": "int";
                    case "Float": "float";
                    case "Void": "void";
                    default:
                        Context.error('Typed interface boundary does not support abstract type $name', pos);
                        "unsupported";
                };
                macro new haxiom.ProxyBoundaryType($v{kind}, $v{nullable});
            case TInst(ref, params):
                var classType = ref.get();
                var name = classType.pack.concat([classType.name]).join(".");
                switch (name) {
                    case "String": macro new haxiom.ProxyBoundaryType("string", $v{nullable});
                    case "haxe.io.Bytes": macro new haxiom.ProxyBoundaryType("bytes", $v{nullable});
                    case "Array":
                        if (params.length != 1)
                            Context.error("Array boundary type requires one type parameter", pos);
                        var element = boundaryType(params[0], pos);
                        macro new haxiom.ProxyBoundaryType("array", $v{nullable}, $element);
                    case "haxiom.HostRef": macro new haxiom.ProxyBoundaryType("hostref", true);
                    default:
                        Context.error('Typed interface boundary does not support class type $name; use a supported structure or haxiom.HostRef', pos);
                        macro new haxiom.ProxyBoundaryType("unsupported");
                }
            case TAnonymous(ref):
                var fields = [];
                for (field in ref.get().fields) {
                    var fieldType = boundaryType(field.type, field.pos);
                    var optional = field.meta.has(":optional");
                    fields.push(macro new haxiom.ProxyBoundaryType.ProxyBoundaryField($v{field.name}, $fieldType, $v{optional}));
                }
                macro new haxiom.ProxyBoundaryType("anonymous", $v{nullable}, null, $a{fields});
            case TDynamic(_): macro new haxiom.ProxyBoundaryType("dynamic", true);
            case TFun(_, _):
                Context.error("Functions cannot cross a typed interface boundary", pos);
                macro new haxiom.ProxyBoundaryType("unsupported");
            case TEnum(ref, _):
                var enumType = ref.get();
                var name = enumType.pack.concat([enumType.name]).join(".");
                Context.error('Typed interface boundary does not yet support enum type $name', pos);
                macro new haxiom.ProxyBoundaryType("unsupported");
            default:
                Context.error('Unsupported typed interface boundary type ${haxe.macro.TypeTools.toString(type)}', pos);
                macro new haxiom.ProxyBoundaryType("unsupported");
        }
    }

    private static function generateProxy(interfaceType:Type):String {
        switch (Context.follow(interfaceType)) {
            case TInst(tRef, _):
                var t = tRef.get();
                if (!t.isInterface) {
                    Context.error("Expected interface type, got " + t.name, Context.currentPos());
                }
                
                var interfaceFqName = t.pack.join(".") + (t.pack.length > 0 ? "." : "") + t.name;
                var proxyClassName = "Proxy_" + interfaceFqName.split(".").join("_");
                var proxyFqName = "haxiom.proxies." + proxyClassName;
                
                if (definedProxies.exists(proxyFqName)) {
                    return proxyFqName;
                }
                definedProxies.set(proxyFqName, true);
                
                var fields:Array<Field> = [];
                
                // 1. Instance variables: _haxiom and _guest
                fields.push({
                    name: "_haxiom",
                    access: [],
                    pos: Context.currentPos(),
                    kind: FVar(macro : haxiom.Haxiom)
                });
                fields.push({
                    name: "_guest",
                    access: [],
                    pos: Context.currentPos(),
                    kind: FVar(macro : Dynamic)
                });
                
                // 2. Constructor: public function new(haxiom:haxiom.Haxiom, guest:Dynamic)
                fields.push({
                    name: "new",
                    access: [APublic],
                    pos: Context.currentPos(),
                    kind: FFun({
                        args: [
                            { name: "haxiom", type: macro : haxiom.Haxiom },
                            { name: "guest", type: macro : Dynamic }
                        ],
                        ret: null,
                        expr: macro {
                            this._haxiom = haxiom;
                            this._guest = guest;
                        }
                    })
                });
                
                // Recursively collect all methods/properties (including parent interfaces)
                var allFields:Map<String, ClassField> = new Map();
                function collectFields(itf:ClassType) {
                    for (field in itf.fields.get()) {
                        allFields.set(field.name, field);
                    }
                    for (parent in itf.interfaces) {
                        collectFields(parent.t.get());
                    }
                }
                collectFields(t);
                var accessorFields:Array<String> = [];
                for (field in allFields) {
                    switch (field.kind) {
                        case FVar(_, _):
                            accessorFields.push("get_" + field.name);
                            accessorFields.push("set_" + field.name);
                        default:
                    }
                }
                for (name in accessorFields) {
                    allFields.remove(name);
                }
                
                // 3. Delegation Fields
                for (field in allFields) {
                    var fieldName = field.name;
                    var fieldType = field.type;
                    var complexType = Context.toComplexType(fieldType);
                    
                    switch (field.kind) {
                        case FMethod(_):
                            // Method delegation
                            switch (Context.follow(fieldType)) {
                                case TFun(args, retType):
                                    var methodArgs:Array<FunctionArg> = [];
                                    var callArgsExprs:Array<Expr> = [];
                                    var argBoundaryTypes:Array<Expr> = [];
                                    
                                    for (arg in args) {
                                        methodArgs.push({
                                            name: arg.name,
                                            type: Context.toComplexType(arg.t),
                                            opt: arg.opt
                                        });
                                        callArgsExprs.push({ expr: EConst(CIdent(arg.name)), pos: Context.currentPos() });
                                        argBoundaryTypes.push(boundaryType(arg.t, field.pos));
                                    }
                                    
                                    var retTypeExpr = Context.toComplexType(retType);
                                    var isVoid = (haxe.macro.TypeTools.toString(retType) == "Void");
                                    var returnBoundaryType = boundaryType(retType, field.pos);
                                    
                                    var delegationExpr = if (isVoid) {
                                        macro {
                                            this._haxiom.invokeProxyMethod(this._guest, $v{fieldName}, $a{callArgsExprs}, $a{argBoundaryTypes}, $returnBoundaryType);
                                        };
                                    } else {
                                        macro {
                                            return this._haxiom.invokeProxyMethod(this._guest, $v{fieldName}, $a{callArgsExprs}, $a{argBoundaryTypes}, $returnBoundaryType);
                                        };
                                    };
                                    
                                    fields.push({
                                        name: fieldName,
                                        access: [APublic],
                                        pos: Context.currentPos(),
                                        kind: FFun({
                                            args: methodArgs,
                                            ret: retTypeExpr,
                                            expr: delegationExpr
                                        })
                                    });
                                default:
                            }
                        case FVar(read, write):
                            // Variable/Property delegation
                            if (read == AccNormal || write == AccNormal) {
                                Context.error('Interface field $fieldName must use delegating accessors such as (get, never) or (get, set)', field.pos);
                            }
                            var canRead = switch (read) {
                                case AccNo | AccNever: false;
                                default: true;
                            };
                            var canWrite = switch (write) {
                                case AccNo | AccNever: false;
                                default: true;
                            };
                            var propertyBoundaryType = boundaryType(fieldType, field.pos);
                            fields.push({
                                name: fieldName,
                                access: [APublic],
                                pos: Context.currentPos(),
                                kind: FProp(canRead ? "get" : "never", canWrite ? "set" : "never", complexType)
                            });
                            if (canRead) {
                                fields.push({
                                    name: "get_" + fieldName,
                                    access: [APublic],
                                    pos: Context.currentPos(),
                                    kind: FFun({
                                        args: [],
                                        ret: complexType,
                                        expr: macro {
                                            return this._haxiom.readProxyField(this._guest, $v{fieldName}, $propertyBoundaryType);
                                        }
                                    })
                                });
                            }
                            if (canWrite) {
                                fields.push({
                                    name: "set_" + fieldName,
                                    access: [APublic],
                                    pos: Context.currentPos(),
                                    kind: FFun({
                                        args: [{ name: "value", type: complexType }],
                                        ret: complexType,
                                        expr: macro {
                                            return this._haxiom.writeProxyField(this._guest, $v{fieldName}, value, $propertyBoundaryType);
                                        }
                                    })
                                });
                            }
                    }
                }
                
                // Define the compile-time proxy class
                var typeDef:TypeDefinition = {
                    pack: ["haxiom", "proxies"],
                    name: proxyClassName,
                    pos: Context.currentPos(),
                    kind: TDClass(null, [{ pack: t.pack, name: t.name }]),
                    fields: fields
                };
                Context.defineType(typeDef);
                return proxyFqName;
                
            default:
                Context.error("Expected class instance type for interface, got " + interfaceType, Context.currentPos());
                return null;
        }
    }
}
#end
