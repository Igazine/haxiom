package haxiom.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

class ProxyGenerator {
    static var definedProxies:Map<String, Bool> = new Map();

    public static function generateProxy(interfaceType:Type):String {
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
                                    
                                    for (arg in args) {
                                        methodArgs.push({
                                            name: arg.name,
                                            type: Context.toComplexType(arg.t),
                                            opt: arg.opt
                                        });
                                        callArgsExprs.push({ expr: EConst(CIdent(arg.name)), pos: Context.currentPos() });
                                    }
                                    
                                    var retTypeExpr = Context.toComplexType(retType);
                                    var isVoid = (haxe.macro.TypeTools.toString(retType) == "Void");
                                    
                                    var delegationExpr = if (isVoid) {
                                        macro {
                                            var func = this._haxiom.resolveField(this._guest, $v{fieldName});
                                            if (func != null) {
                                                Reflect.callMethod(null, func, $a{callArgsExprs});
                                            } else {
                                                throw "Method " + $v{fieldName} + " not implemented on guest class";
                                            }
                                        };
                                    } else {
                                        macro {
                                            var func = this._haxiom.resolveField(this._guest, $v{fieldName});
                                            if (func != null) {
                                                return Reflect.callMethod(null, func, $a{callArgsExprs});
                                            } else {
                                                throw "Method " + $v{fieldName} + " not implemented on guest class";
                                            }
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
                        default:
                            // Variable/Property delegation
                            fields.push({
                                name: fieldName,
                                access: [APublic],
                                pos: Context.currentPos(),
                                kind: FProp("get", "set", complexType)
                            });
                            
                            fields.push({
                                name: "get_" + fieldName,
                                access: [APublic],
                                pos: Context.currentPos(),
                                kind: FFun({
                                    args: [],
                                    ret: complexType,
                                    expr: macro {
                                        return this._haxiom.resolveField(this._guest, $v{fieldName});
                                    }
                                })
                            });
                            
                            fields.push({
                                name: "set_" + fieldName,
                                access: [APublic],
                                pos: Context.currentPos(),
                                kind: FFun({
                                    args: [{ name: "value", type: complexType }],
                                    ret: complexType,
                                    expr: macro {
                                        this._haxiom.setField(this._guest, $v{fieldName}, value);
                                        return value;
                                    }
                                })
                            });
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
