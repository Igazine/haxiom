package;

import feathers.controls.Application;
import feathers.controls.Button;
import feathers.controls.Label;
import feathers.controls.LayoutGroup;
import feathers.controls.PopUpListView;
import feathers.core.FeathersControl;
import feathers.data.ArrayCollection;
import feathers.events.TriggerEvent;
import feathers.layout.HorizontalAlign;
import feathers.layout.HorizontalLayout;
import feathers.layout.HorizontalLayoutData;
import feathers.layout.VerticalAlign;
import feathers.layout.VerticalLayout;
import feathers.layout.VerticalLayoutData;
import feathers.skins.RectangleSkin;
import feathers.style.IDarkModeTheme;
import feathers.style.Theme;
import haxe.Timer;
import haxe.io.Bytes;
import haxiom.Haxiom;
import openfl.events.Event;

class TestOpenFL extends Application {
	static final SCRIPTS:Array<ScriptDef> = [
		{
			id: "Basic.hx",
			name: "1. Basic FeathersUI Example",
			path: "./scripts/Basic.hx"
		},
		{
			id: "SnakeGame.hx",
			name: "2. Snake Game (Multi-Module Script)",
			path: "./scripts/SnakeGame.hx"
		},
		{
			id: "BitmapLoader.hxbc",
			name: "3. Pre-compiled Bytecode (Embedded Asset)",
			path: "./scripts/BitmapLoader.hxbc",
			isBytecode: true
		},
		{
			id: "Shapes.hx",
			name: "4. OpenFL Drawing Shapes",
			path: "./scripts/Shapes.hx"
		},
		{
			id: "Sandboxing.hx",
			name: "5. Sandboxing & Security Filter",
			path: "./scripts/Sandboxing.hx"
		},
		{
			id: "Million.hx",
			name: "6. Performance Benchmark (1M Instructions)",
			path: "./scripts/Million.hx"
		}
	];

	var scriptArea:ScriptArea;
	var executeButton:Button;
	var dropdown:PopUpListView;
	var container:LayoutGroup;
	var selectedScript:ScriptDef;

	public function new() {
		var theme = cast(Theme.fallbackTheme, IDarkModeTheme);
		theme.darkMode = true;

		super();
		initUI();
	}

	function initUI() {
		// Main Layout
		var mainLayout = new HorizontalLayout();
		mainLayout.gap = 10;
		mainLayout.setPadding(10);
		this.layout = mainLayout;

		// Left Panel (Script Selection & Editor)
		var leftPanel = new LayoutGroup();
		leftPanel.layoutData = new HorizontalLayoutData(100, 100);
		var leftLayout = new VerticalLayout();
		leftLayout.gap = 10;
		leftLayout.horizontalAlign = HorizontalAlign.CENTER;
		leftPanel.layout = leftLayout;
		this.addChild(leftPanel);

		dropdown = new PopUpListView();
		dropdown.dataProvider = new ArrayCollection(SCRIPTS);
		dropdown.layoutData = new VerticalLayoutData(100);
		dropdown.itemToText = function(item:Dynamic) return item.name;
		dropdown.addEventListener(Event.CHANGE, (event) -> {
			selectedScript = dropdown.selectedItem;
			loadScript();
		});
		leftPanel.addChild(dropdown);

		scriptArea = new ScriptArea();
		scriptArea.text = "";
		scriptArea.layoutData = new VerticalLayoutData(100, 100);
		leftPanel.addChild(scriptArea);

		executeButton = new Button();
		executeButton.text = "Execute Haxiom Script";
		executeButton.layoutData = new HorizontalLayoutData(100, 100);
		executeButton.addEventListener(TriggerEvent.TRIGGER, onExecuteTrigger);
		leftPanel.addChild(executeButton);

		// Right Panel (Render Canvas Container)
		var rightPanel = new LayoutGroup();
		rightPanel.layoutData = new HorizontalLayoutData(100, 100);
		var rightLayout = new VerticalLayout();
		rightLayout.gap = 10;
		rightPanel.layout = rightLayout;
		this.addChild(rightPanel);

		var label = new Label("Shared Render Container");
		rightPanel.addChild(label);

		container = new LayoutGroup();
		container.backgroundSkin = new RectangleSkin(FillStyle.SolidColor(0x181818), LineStyle.SolidColor(1, 0));
		container.layoutData = new VerticalLayoutData(100, 100);
		var containerLayout = new VerticalLayout();
		containerLayout.gap = 10;
		containerLayout.horizontalAlign = HorizontalAlign.CENTER;
		containerLayout.verticalAlign = VerticalAlign.MIDDLE;
		container.layout = containerLayout;
		rightPanel.addChild(container);

		selectedScript = SCRIPTS[0];
		loadScript();
	}

	function registerFFI(haxiom:Haxiom) {
		// FeathersUI Controls
		haxiom.exposeClass("feathers.core.FeathersControl", FeathersControl);
		haxiom.exposeClass("feathers.controls.Button", Button);
		haxiom.exposeClass("feathers.controls.Alert", feathers.controls.Alert);
		haxiom.exposeClass("feathers.controls.Label", Label);
		haxiom.exposeClass("feathers.controls.LayoutGroup", LayoutGroup);
		haxiom.exposeClass("feathers.events.TriggerEvent", TriggerEvent);

		// OpenFL Display & UI
		haxiom.exposePackage("openfl.display.*");
		haxiom.exposeClass("openfl.text.TextField", openfl.text.TextField);
		haxiom.exposeClass("openfl.text.TextFormat", openfl.text.TextFormat);
		haxiom.exposeClass("openfl.events.KeyboardEvent", openfl.events.KeyboardEvent);
		haxiom.exposeClass("openfl.events.MouseEvent", openfl.events.MouseEvent);
		haxiom.exposeClass("openfl.events.Event", openfl.events.Event);
		haxiom.exposeClass("openfl.ui.Keyboard", openfl.ui.Keyboard);
		haxiom.exposeClass("openfl.utils.Assets", openfl.utils.Assets);
		haxiom.exposeClass("lime.app.Future", lime.app.Future);

		// Haxe Core Utilities
		haxiom.exposeClass("haxe.Timer", haxe.Timer);
	}

	function registerGlobals(haxiom:Haxiom) {
		haxiom.setGlobal("ScriptContext", {
			container: container,
			gameRoot: container,
			sandboxedContainer: {
				addChild: function(child:FeathersControl) {
					container.addChild(child);
				}
			}
		});

		// Dynamic module resolver for multi-module scripts (e.g. SnakeGame importing snake.entities.*)
		haxiom.moduleResolver = function(moduleName:String):String {
			var path = "scripts/" + StringTools.replace(moduleName, ".", "/") + ".hx";
			if (openfl.utils.Assets.exists(path)) {
				return openfl.utils.Assets.getText(path);
			}
			return null;
		};
	}

	function loadScript() {
		container.removeChildren();
		scriptArea.load(selectedScript);
	}

	function onExecuteTrigger(e:TriggerEvent) {
		container.removeChildren();
		trace("Executing script: " + scriptArea.currentScript.name + "...");

		final haxiom = new Haxiom();
		haxiom.useVM = true;
		registerFFI(haxiom);
		registerGlobals(haxiom);

		final t = Timer.stamp();
		try {
			if (scriptArea.currentScript.isBytecode) {
				haxiom.executeBytecodeBytes(scriptArea.currentScriptContent);
			} else {
				haxiom.currentFilename = scriptArea.currentScript.id;
				haxiom.interpret(scriptArea.currentScriptContent.toString());
			}
		} catch (err:Dynamic) {
			trace("SCRIPT EXCEPTION ERROR: " + err);
			trace("STACK TRACE: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		final duration = (Timer.stamp() - t);
		if (duration < 1) {
			trace("Script executed in " + (duration * 1000) + " milliseconds");
		} else {
			trace("Script executed in " + duration + " seconds");
		}
	}
}

typedef ScriptDef = {
	id:String,
	path:String,
	name:String,
	?isBytecode:Bool,
	?context:Array<ScriptContext>,
}

typedef ScriptContext = {
	fqName:String,
	cls:Class<Dynamic>,
}

class HaxiomTimer {
	public static function delay(ms:Int):haxiom.guest.Future {
		var fut = new haxiom.guest.Future();
		haxe.Timer.delay(function() {
			fut.resolve(null);
		}, ms);
		return fut;
	}
}
