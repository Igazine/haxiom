package haxiom;

typedef Pos = {
    var line:Int;
    var col:Int;
    var ?file:String;
}

enum TokenDef {
    TEof;
    TNewline;
    TIdent(v:String);
    TInt(v:Int);
    TFloat(v:Float);
    TString(v:String);
    TEReg(pattern:String, flags:String);
    
    // Keywords
    TBreak;
    TCase;
    TClass;
    TContinue;
    TDefault;
    TDo;
    TElse;
    TExtends;
    TFalse;
    TFor;
    TFunction;
    TIf;
    TIn;
    TNew;
    TNull;
    TPrivate;
    TPublic;
    TReturn;
    TStatic;
    TSuper;
    TSwitch;
    TThis;
    TTrue;
    TVar;
    TWhile;
    TImport;
    TTry;
    TCatch;
    TThrow;
    TFinal;
    TCast;
    TPackage;
    TInterface;
    TImplements;
    TEnum;
    TUsing;
    TAbstract;
    TOverride;
    TTypedef;
    TInline;
    TMacro;
    
    // Operators
    TPlus;
    TMinus;
    TStar;
    TSlash;
    TPercent;
    TIncrement;
    TDecrement;
    
    TAssign;
    TPlusAssign;
    TMinusAssign;
    TStarAssign;
    TSlashAssign;
    TPercentAssign;
    
    TEqual;
    TNotEqual;
    TLess;
    TLessEqual;
    TGreater;
    TGreaterEqual;
    
    TAnd;
    TOr;
    TNot;
    
    TBitAnd;
    TBitOr;
    TBitXor;
    TBitNot;
    TShiftLeft;
    TShiftRight;
    TUnsignedShiftRight;
    
    TQuestion;
    TColon;
    TDot;
    TComma;
    TSemicolon;
    
    TParenOpen;
    TParenClose;
    TBracketOpen;
    TBracketClose;
    TBraceOpen;
    TBraceClose;
    
    TMapArrow; // =>
    TArrow;    // ->
    TDotDotDot;
    TDoubleQuestion;
    TQuestionDot;
    TAt;
}

typedef Token = {
    var def:TokenDef;
    var pos:Pos;
}

enum TypeDecl {
    TPath(path:Array<String>, params:Array<TypeDecl>);
    TFun(args:Array<TypeDecl>, ret:TypeDecl);
    TAnonymous(fields:Array<{name:String, type:TypeDecl, ?opt:Bool}>);
}

typedef FunctionArg = {name:String, type:Null<TypeDecl>, ?isRest:Bool};

enum ExprDef {
    EValue(v:Dynamic);
    EIdent(v:String);
    EEReg(pattern:String, flags:String);
    EVar(name:String, type:Null<TypeDecl>, ?expr:Expr, ?isFinal:Bool, ?meta:Array<{name:String, params:Array<Expr>}>);
    EAssign(target:Expr, expr:Expr);
    EBinop(op:String, e1:Expr, e2:Expr);
    EUnop(op:String, e:Expr);
    
    EField(e:Expr, field:String);
    ECall(e:Expr, args:Array<Expr>);
    
    EArrayDecl(values:Array<Expr>);
    EObjectDecl(fields:Array<{name:String, expr:Expr}>);
    EMapDecl(values:Array<{key:Expr, value:Expr}>);
    
    EClass(name:String, 
           fields:Array<{name:String, type:Null<TypeDecl>, expr:Expr, isStatic:Bool, isPublic:Bool, isFinal:Bool, ?property:{get:String, set:String}, ?meta:Array<{name:String, params:Array<Expr>}>}>, 
           methods:Array<{name:String, args:Array<FunctionArg>, retType:Null<TypeDecl>, body:Null<Expr>, isStatic:Bool, isPublic:Bool, ?isOverride:Bool, ?isAbstract:Bool, ?meta:Array<{name:String, params:Array<Expr>}>}>, 
           ?parent:TypeDecl,
           ?interfaces:Array<TypeDecl>,
           ?params:Array<String>,
           ?meta:Array<{name:String, params:Array<Expr>}>);

    EBlock(exprs:Array<Expr>);
    EFunction(?name:String, args:Array<FunctionArg>, retType:Null<TypeDecl>, body:Expr);
    
    EIf(cond:Expr, e1:Expr, ?e2:Expr);
    EWhile(cond:Expr, e:Expr);
    EDoWhile(cond:Expr, e:Expr);
    EFor(v:String, it:Expr, e:Expr);
    ESwitch(expr:Expr, cases:Array<{values:Array<Expr>, ?guard:Expr, expr:Expr}>, ?defExpr:Expr);
    EReturn(?e:Expr);
    EBreak;
    EContinue;
    
    EPackage(path:Array<String>);
    EImport(path:Array<String>, ?alias:String);
    EUsing(path:Array<String>);
    EThrow(expr:Expr);
    ETry(tryExpr:Expr, catches:Array<{pattern:Expr, ?type:TypeDecl, ?guard:Expr, body:Expr}>);
    ECast(expr:Expr, ?type:TypeDecl);
    EInterface(name:String, fields:Array<{name:String, type:Null<TypeDecl>, ?property:{get:String, set:String}, ?meta:Array<{name:String, params:Array<Expr>}>}>, methods:Array<{name:String, args:Array<FunctionArg>, retType:Null<TypeDecl>, ?body:Null<Expr>, ?meta:Array<{name:String, params:Array<Expr>}>}>, ?parents:Array<TypeDecl>, ?params:Array<String>, ?meta:Array<{name:String, params:Array<Expr>}>);
    EEnum(name:String, constructors:Array<{name:String, args:Null<Array<FunctionArg>>}>, ?params:Array<String>);
    ESafeField(e:Expr, field:String);
    ENew(type:TypeDecl, args:Array<Expr>);
    EAbstract(name:String, underlyingType:TypeDecl, fields:Array<{name:String, type:Null<TypeDecl>, expr:Expr, isStatic:Bool, isPublic:Bool, isFinal:Bool, ?property:{get:String, set:String}, ?meta:Array<{name:String, params:Array<Expr>}>}>, methods:Array<{name:String, args:Array<FunctionArg>, retType:Null<TypeDecl>, body:Expr, isStatic:Bool, isPublic:Bool, ?meta:Array<{name:String, params:Array<Expr>}>}>, ?params:Array<String>, ?meta:Array<{name:String, params:Array<Expr>}>);
    ETypedef(name:String, type:TypeDecl, ?params:Array<String>);
    EMeta(meta:Array<{name:String, params:Array<Expr>}>, expr:Expr);
}

typedef Expr = {
    var def:ExprDef;
    var pos:Pos;
}
