package haxiom.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Compiler;
#end

class FFIMacro {
    /**
     * Globally hooks all compiled classes to apply the build macro,
     * removing the need for manual package listing.
     */
    public static function initialize():Void {
        #if macro
        
        var coreClasses = [
            "Date", "DateTools", "StringBuf", "Xml", "haxe.Timer", "haxe.Json",
            "haxe.io.Bytes", "haxe.io.BytesBuffer", "haxe.io.BytesInput", "haxe.io.BytesOutput",
            "haxe.io.Path", "haxe.io.Input", "haxe.io.Output", "haxe.io.Eof", "haxe.io.Error", "haxe.io.StringInput",
            "haxe.ds.List", "haxe.ds.StringMap", "haxe.ds.IntMap", "haxe.ds.ObjectMap", "haxe.ds.WeakMap",
            "haxe.ds.HashMap", "haxe.ds.Vector", "haxe.ds.ArraySort", "haxe.ds.BalancedTree",
            "haxe.ds.EnumValueMap", "haxe.ds.Option", "haxe.ds.ReadOnlyArray",
            "StringTools", "Lambda", "Std", "Math", "Reflect", "Type",
            "haxe.crypto.Md5", "haxe.crypto.Sha1", "haxe.crypto.Sha224", "haxe.crypto.Sha256",
            "haxe.crypto.Adler32", "haxe.crypto.Crc32", "haxe.crypto.Hmac", "haxe.crypto.BaseCode",
            "haxe.iterators.ArrayIterator", "haxe.iterators.ArrayKeyValueIterator", "haxe.iterators.MapKeyValueIterator",
            "haxe.iterators.StringIterator", "haxe.iterators.StringKeyValueIterator",
            "haxe.rtti.Meta", "haxe.rtti.Rtti",
            "haxe.xml.Access", "haxe.xml.Parser", "haxe.xml.Printer",
            "haxe.Exception", "haxe.ValueException", "haxe.IMap"
        ];
        
        // Dynamically define a class that references all core classes to force compiling them
        var fields = [];
        var pos = Context.currentPos();
        var i = 0;
        for (cls in coreClasses) {
            try {
                Compiler.keep(cls);
                var t = Context.getType(cls);
                var isClass = false;
                switch (t) {
                    case TInst(classRef, _):
                        var c = classRef.get();
                        if (!c.isInterface) {
                            isClass = true;
                        }
                    default:
                }
                if (isClass) {
                    var clsExpr = Context.parseInlineString(cls, pos);
                    fields.push({
                        name: "ref" + i,
                        pos: pos,
                        kind: FieldType.FVar(macro:Dynamic, clsExpr),
                        access: [APublic, AStatic]
                    });
                    i++;
                }
            } catch (e:Dynamic) {}
        }
        
        var t:haxe.macro.Expr.TypeDefinition = {
            pack: ["haxiom", "macro"],
            name: "StdlibKeep",
            pos: pos,
            kind: TDClass(),
            fields: fields
        };
        Context.defineType(t);
        Compiler.keep("haxiom.macro.StdlibKeep");
        
        Context.onAfterTyping(function(modules) {
            for (module in modules) {
                var pack:Array<String> = [];
                var name:String = "";
                var moduleName:String = "";
                var isExposed = false;
                
                switch (module) {
                    case TClassDecl(classRef):
                        var cls = classRef.get();
                        pack = cls.pack;
                        name = cls.name;
                        moduleName = cls.module;
                        
                        var fqName = cls.pack.concat([cls.name]).join(".");
                        if (cls.meta.has(":haxiom.expose")) {
                            isExposed = true;
                            if (exposedClasses.indexOf(fqName) == -1) {
                                exposedClasses.push(fqName);
                            }
                            if (!cls.meta.has(":keep")) {
                                cls.meta.add(":keep", [], cls.pos);
                            }
                            if (cls.constructor != null) {
                                cls.constructor.get().meta.add(":keep", [], cls.pos);
                            }
                            for (field in cls.fields.get()) {
                                if (!field.meta.has(":keep")) {
                                    field.meta.add(":keep", [], field.pos);
                                }
                            }
                            for (field in cls.statics.get()) {
                                if (!field.meta.has(":keep")) {
                                    field.meta.add(":keep", [], field.pos);
                                }
                            }
                            if (cls.params.length > 0) {
                                var found = false;
                                for (b in genericBases) {
                                    if (b.pack.join(".") == cls.pack.join(".") && b.name == cls.name) {
                                        found = true;
                                        break;
                                    }
                                }
                                if (!found) {
                                    genericBases.push(cls);
                                }
                            }
                        }
                    case TEnumDecl(enumRef):
                        var enm = enumRef.get();
                        pack = enm.pack;
                        name = enm.name;
                        moduleName = enm.module;
                    case TTypeDecl(defRef):
                        var tdef = defRef.get();
                        pack = tdef.pack;
                        name = tdef.name;
                        moduleName = tdef.module;
                    case TAbstract(abstractRef):
                        var abs = abstractRef.get();
                        pack = abs.pack;
                        name = abs.name;
                        moduleName = abs.module;
                        
                        if (abs.meta.has(":haxiom.expose")) {
                            isExposed = true;
                            var fqName = abs.pack.concat([abs.name]).join(".");
                            if (abs.impl != null) {
                                var implClass = abs.impl.get();
                                var fqImplName = implClass.pack.concat([implClass.name]).join(".");
                                
                                var methods = [];
                                for (field in implClass.statics.get()) {
                                    methods.push(field.name);
                                }
                                
                                exposedAbstracts.set(fqName, {
                                    implClass: fqImplName,
                                    methods: methods,
                                    underlying: haxe.macro.TypeTools.toString(abs.type)
                                });
                                
                                Compiler.keep(fqImplName);
                                
                                if (!implClass.meta.has(":keep")) {
                                    implClass.meta.add(":keep", [], implClass.pos);
                                }
                                for (field in implClass.statics.get()) {
                                    if (!field.meta.has(":keep")) {
                                        field.meta.add(":keep", [], field.pos);
                                    }
                                }
                            }
                        }
                }
                
                if (isExposed && moduleName != null && moduleName != "") {
                    var runtimePath = pack.concat([name]).join(".");
                    var list = exposedModules.get(moduleName);
                    if (list == null) {
                        list = [];
                        exposedModules.set(moduleName, list);
                    }
                    if (list.indexOf(runtimePath) == -1) {
                        list.push(runtimePath);
                    }
                }
            }
            
            // Discover generated generic instantiations
            for (module in modules) {
                switch (module) {
                    case TClassDecl(classRef):
                        var cls = classRef.get();
                        for (base in genericBases) {
                            if (cls.pack.join(".") == base.pack.join(".") && cls.name.indexOf(base.name + "_") == 0) {
                                var baseFq = base.pack.concat([base.name]).join(".");
                                var clsFq = cls.pack.concat([cls.name]).join(".");
                                var suffix = cls.name.substr(base.name.length + 1);
                                var paramPart = suffix.split("_").join(".");
                                var genericSig = baseFq + "<" + paramPart + ">";
                                
                                exposedGenerics.set(genericSig, clsFq);
                                
                                if (!cls.meta.has(":keep")) {
                                    cls.meta.add(":keep", [], cls.pos);
                                }
                                if (cls.constructor != null) {
                                    cls.constructor.get().meta.add(":keep", [], cls.pos);
                                }
                                for (field in cls.fields.get()) {
                                    if (!field.meta.has(":keep")) {
                                        field.meta.add(":keep", [], field.pos);
                                    }
                                }
                                for (field in cls.statics.get()) {
                                    if (!field.meta.has(":keep")) {
                                        field.meta.add(":keep", [], field.pos);
                                    }
                                }
                            }
                        }
                    default:
                }
            }
            
            if (!registryDefined) {
                registryDefined = true;
                var initExpr = macro haxiom.macro.FFIMacro.getAbstractMap();
                
                var t:haxe.macro.Expr.TypeDefinition = {
                    pack: ["haxiom", "macro"],
                    name: "AbstractRegistry",
                    pos: Context.currentPos(),
                    kind: TDClass(),
                    fields: [
                        {
                            name: "impls",
                            pos: Context.currentPos(),
                            kind: FieldType.FVar(macro:Map<String, Dynamic>, initExpr),
                            access: [APublic, AStatic]
                        }
                    ]
                };
                Context.defineType(t);
                Compiler.keep("haxiom.macro.AbstractRegistry");
            }
            
            if (!stdlibRegistryDefined) {
                stdlibRegistryDefined = true;
                var initExpr = macro haxiom.macro.FFIMacro.getStdlibMap();
                
                var t:haxe.macro.Expr.TypeDefinition = {
                    pack: ["haxiom", "macro"],
                    name: "StdlibRegistry",
                    pos: Context.currentPos(),
                    kind: TDClass(),
                    fields: [
                        {
                            name: "classes",
                            pos: Context.currentPos(),
                            kind: FieldType.FVar(macro:Map<String, Dynamic>, initExpr),
                            access: [APublic, AStatic]
                        }
                    ]
                };
                Context.defineType(t);
                Compiler.keep("haxiom.macro.StdlibRegistry");
            }

            // Serialize and add resources here (in onAfterTyping)
            var classesJson = haxe.Json.stringify(exposedClasses);
            Context.addResource("haxiom_exposed_classes", haxe.io.Bytes.ofString(classesJson));
            
            var abstractsObj = {};
            for (k in exposedAbstracts.keys()) {
                Reflect.setField(abstractsObj, k, exposedAbstracts.get(k));
            }
            var abstractsJson = haxe.Json.stringify(abstractsObj);
            Context.addResource("haxiom_exposed_abstracts", haxe.io.Bytes.ofString(abstractsJson));
            
            var genericsObj = {};
            for (k in exposedGenerics.keys()) {
                Reflect.setField(genericsObj, k, exposedGenerics.get(k));
            }
            var genericsJson = haxe.Json.stringify(genericsObj);
            Context.addResource("haxiom_exposed_generics", haxe.io.Bytes.ofString(genericsJson));
            
            var modulesObj = {};
            for (k in exposedModules.keys()) {
                Reflect.setField(modulesObj, k, exposedModules.get(k));
            }
            var modulesJson = haxe.Json.stringify(modulesObj);
            Context.addResource("haxiom_exposed_modules", haxe.io.Bytes.ofString(modulesJson));
        });
        #end
    }

    public static macro function getAbstractMap():haxe.macro.Expr {
        #if macro
        var exprs = [];
        for (k in exposedAbstracts.keys()) {
            var absInfo = exposedAbstracts.get(k);
            var fqName = k;
            
            var expr:haxe.macro.Expr;
            if (haxe.macro.Context.defined("js")) {
                var jsVar = fqName.split(".").join("_");
                expr = macro js.Syntax.code($v{jsVar});
            } else {
                var parts = absInfo.implClass.split(".");
                for (i in 0...parts.length - 1) {
                    if (StringTools.startsWith(parts[i], "_")) {
                        parts[i] = parts[i].substring(1);
                    }
                }
                var cleanImplClass = parts.join(".");
                expr = macro Type.resolveClass($v{cleanImplClass});
            }
            exprs.push(macro $v{k} => $expr);
        }
        return macro [ $a{exprs} ];
        #else
        return macro null;
        #end
    }

    public static macro function getStdlibMap():haxe.macro.Expr {
        #if macro
        var coreClasses = [
            "Date", "DateTools", "StringBuf", "Xml", "haxe.Timer", "haxe.Json",
            "haxe.io.Bytes", "haxe.io.BytesBuffer", "haxe.io.BytesInput", "haxe.io.BytesOutput",
            "haxe.io.Path", "haxe.io.Input", "haxe.io.Output", "haxe.io.Eof", "haxe.io.Error", "haxe.io.StringInput",
            "haxe.ds.List", "haxe.ds.StringMap", "haxe.ds.IntMap", "haxe.ds.ObjectMap", "haxe.ds.WeakMap",
            "haxe.ds.HashMap", "haxe.ds.Vector", "haxe.ds.ArraySort", "haxe.ds.BalancedTree",
            "haxe.ds.EnumValueMap", "haxe.ds.Option", "haxe.ds.ReadOnlyArray",
            "StringTools", "Lambda", "Std", "Math", "Reflect", "Type",
            "haxe.crypto.Md5", "haxe.crypto.Sha1", "haxe.crypto.Sha224", "haxe.crypto.Sha256",
            "haxe.crypto.Adler32", "haxe.crypto.Crc32", "haxe.crypto.Hmac", "haxe.crypto.BaseCode",
            "haxe.iterators.ArrayIterator", "haxe.iterators.ArrayKeyValueIterator", "haxe.iterators.MapKeyValueIterator",
            "haxe.iterators.StringIterator", "haxe.iterators.StringKeyValueIterator",
            "haxe.rtti.Meta", "haxe.rtti.Rtti",
            "haxe.xml.Access", "haxe.xml.Parser", "haxe.xml.Printer",
            "haxe.Exception", "haxe.ValueException", "haxe.IMap"
        ];
        var exprs = [];
        var pos = haxe.macro.Context.currentPos();
        for (cls in coreClasses) {
            try {
                var t = haxe.macro.Context.getType(cls);
                var isClass = false;
                switch (t) {
                    case TInst(classRef, _):
                        var c = classRef.get();
                        if (!c.isInterface) {
                            isClass = true;
                        }
                    default:
                }
                if (isClass) {
                    var clsExpr = haxe.macro.Context.parseInlineString(cls, pos);
                    exprs.push(macro $v{cls} => $clsExpr);
                }
            } catch (e:Dynamic) {}
        }
        return macro [ $a{exprs} ];
        #else
        return macro null;
        #end
    }

    #if macro
    static var registryDefined = false;
    static var stdlibRegistryDefined = false;
    static var exposedClasses:Array<String> = [];
    static var exposedAbstracts = new Map<String, { implClass: String, methods: Array<String>, underlying: String }>();
    static var exposedGenerics = new Map<String, String>();
    static var exposedModules = new Map<String, Array<String>>();
    static var genericBases:Array<ClassType> = [];

    public static function build():Array<Field> {
        var localClass = Context.getLocalClass();
        if (localClass == null) return null;
        
        var cls = localClass.get();
        
        // Check if the class has @:haxiom.expose metadata
        var hasMeta = cls.meta.has(":haxiom.expose");
        if (hasMeta) {
            // Add @:keep to the class if not already present
            if (!cls.meta.has(":keep")) {
                cls.meta.add(":keep", [], cls.pos);
            }
            
            // Add @:keep to constructor to prevent DCE pruning it
            if (cls.constructor != null) {
                cls.constructor.get().meta.add(":keep", [], cls.pos);
            }
            
            var fields = Context.getBuildFields();
            for (f in fields) {
                if (f.meta == null) {
                    f.meta = [];
                }
                var hasKeep = false;
                for (m in f.meta) {
                    if (m.name == ":keep") {
                        hasKeep = true;
                        break;
                    }
                }
                if (!hasKeep) {
                    f.meta.push({ name: ":keep", pos: f.pos });
                }
            }
            
            var fqName = cls.pack.concat([cls.name]).join(".");
            if (exposedClasses.indexOf(fqName) == -1) {
                exposedClasses.push(fqName);
            }
        }
        
        return null;
    }
    #end
}
