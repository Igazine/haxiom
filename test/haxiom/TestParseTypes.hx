import haxiom.Haxiom;
import sys.io.File;

class TestParseTypes {
    static function main() {
        var engine = new Haxiom();
        try {
            var content = File.getContent("test/haxiom/openfl/scripts/Types.hx");
            var ast = engine.compile(content, "test/haxiom/openfl/scripts/Types.hx");
            trace("Parsed successfully!");
        } catch (e:Dynamic) {
            trace("Parsing failed: " + Std.string(e));
        }
    }
}
