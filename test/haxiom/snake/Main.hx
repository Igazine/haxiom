package;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import haxiom.Haxiom;
import haxiom.FFI;
import haxiom.Future;

class Main extends Sprite {
    var gameRoot:Sprite;
    var engine:Haxiom;

    public function new() {
        super();
        if (stage != null) {
            init();
        } else {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
    }

    function onAddedToStage(e:Event) {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        init();
    }

    function init() {
        // Create root container for the Snake game
        gameRoot = new Sprite();
        addChild(gameRoot);

        // Center the game layout on stage resize and initial load
        stage.addEventListener(Event.RESIZE, onResize);
        onResize(null);

        // Safely forward keyboard events to gameRoot (no direct stage exposure to guest scripts)
        var isForwarding = false;
        stage.addEventListener(KeyboardEvent.KEY_DOWN, function(event:KeyboardEvent) {
            if (isForwarding) return;
            isForwarding = true;
            gameRoot.dispatchEvent(event);
            isForwarding = false;
        });

        // Initialize Haxiom engine
        engine = new Haxiom();
        engine.useVM = true;

        // Set up module resolver for loading packaged guest scripts dynamically
        engine.moduleResolver = function(modulePath:String):String {
            var relativePath = "scripts/" + modulePath.split(".").join("/") + ".hx";
            if (openfl.utils.Assets.exists(relativePath)) {
                return openfl.utils.Assets.getText(relativePath);
            }
            var flatPath = "scripts/" + modulePath + ".hx";
            if (openfl.utils.Assets.exists(flatPath)) {
                return openfl.utils.Assets.getText(flatPath);
            }
            return null;
        };

        // Register FFI classes
        registerFFI(engine);

        // Register exposed globals
        engine.setGlobal("ScriptContext", {
            gameRoot: gameRoot
        });

        // Load and execute the guest Snake script
        try {
            var scriptText = openfl.utils.Assets.getText("scripts/SnakeGame.hx");
            engine.interpret(scriptText);
        } catch (e:Dynamic) {
            trace("Haxiom Snake Boot Error: " + e);
        }
    }

    function onResize(e:Event) {
        // Layout size: 600x650 (600x600 grid, 50px top header)
        gameRoot.x = Math.max(0, (stage.stageWidth - 600) / 2);
        gameRoot.y = Math.max(0, (stage.stageHeight - 650) / 2);
    }

    function registerFFI(haxiom:Haxiom) {
        FFI.registerClass(haxiom, "openfl.display.Sprite", Sprite);
        FFI.registerClass(haxiom, "openfl.display.Shape", openfl.display.Shape);
        FFI.registerClass(haxiom, "openfl.text.TextField", openfl.text.TextField);
        FFI.registerClass(haxiom, "openfl.text.TextFormat", openfl.text.TextFormat);
        FFI.registerClass(haxiom, "openfl.events.MouseEvent", openfl.events.MouseEvent);
        FFI.registerClass(haxiom, "openfl.events.KeyboardEvent", openfl.events.KeyboardEvent);
        FFI.registerClass(haxiom, "openfl.ui.Keyboard", openfl.ui.Keyboard);
        
        // Expose Actuate for visual tweening effects
        FFI.registerClass(haxiom, "motion.Actuate", motion.Actuate);
        
        // Expose a host Timer that maps haxe.Timer.delay to Haxiom Future resolutions
        FFI.registerClass(haxiom, "Timer", HaxiomTimer);
    }
}

class HaxiomTimer {
    public static function delay(ms:Int):Future {
        var fut = new Future();
        haxe.Timer.delay(function() {
            fut.resolve(null);
        }, ms);
        return fut;
    }
}
