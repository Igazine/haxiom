package haxiom;

import haxiom.AST.Pos;

class ScriptException extends haxe.Exception {
    public var rawValue(default, null):Dynamic;
    public var virtualStack(default, null):Array<{method:String, pos:Pos}>;
    public var formattedStackTrace(default, null):String;
    public var line(default, null):Int;
    public var col(default, null):Int;
    public var file(default, null):String;
    public var locals(default, null):Null<Map<String, Dynamic>>;

    public function new(rawValue:Dynamic, virtualStack:Array<{method:String, pos:Pos}>, formattedStackTrace:String, line:Int = 1, col:Int = 1, ?file:String, ?locals:Null<Map<String, Dynamic>> = null) {
        var msg = formattedStackTrace;
        if (locals != null) {
            var localDump = [];
            for (k in locals.keys()) {
                localDump.push('    - $k: ' + Std.string(locals.get(k)));
            }
            if (localDump.length > 0) {
                msg += "\nLocal Variables:\n" + localDump.join("\n");
            }
        }
        super(msg);
        this.rawValue = rawValue;
        this.virtualStack = virtualStack;
        this.formattedStackTrace = msg;
        this.line = line;
        this.col = col;
        this.file = file;
        this.locals = locals;
    }

    public static function makeCodeFrame(source:Null<String>, line:Int, col:Int, file:String):String {
        if (source == null || source == "") return "";
        var lines = source.split("\n");
        if (line < 1 || line > lines.length) return "";
        
        var frame = [];
        var startIdx = line - 2 < 0 ? 0 : line - 2;
        var endIdx = line >= lines.length ? lines.length - 1 : line;
        
        var maxNumWidth = Std.string(endIdx + 1).length;
        
        for (i in startIdx...endIdx + 1) {
            var lineNum = i + 1;
            var prefix = lineNum == line ? ">> " : "   ";
            var lineText = lines[i];
            
            if (StringTools.endsWith(lineText, "\r")) {
                lineText = lineText.substring(0, lineText.length - 1);
            }
            
            var lineNumStr = StringTools.lpad(Std.string(lineNum), " ", maxNumWidth);
            frame.push(prefix + lineNumStr + " | " + lineText);
            
            if (lineNum == line) {
                var pointerSpaces = "";
                var clampedCol = col;
                if (clampedCol < 1) clampedCol = 1;
                if (clampedCol > lineText.length + 1) clampedCol = lineText.length + 1;
                
                for (k in 0...clampedCol - 1) {
                    if (k < lineText.length && lineText.charAt(k) == "\t") {
                        pointerSpaces += "\t";
                    } else {
                        pointerSpaces += " ";
                    }
                }
                
                var pointerPrefix = "";
                for (k in 0...maxNumWidth) {
                    pointerPrefix += " ";
                }
                frame.push("   " + pointerPrefix + " | " + pointerSpaces + "^");
            }
        }
        return frame.join("\n");
    }
}

