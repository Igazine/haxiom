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
import haxiom.FFI;
import haxiom.Haxiom;
import openfl.events.Event;

class TestOpenFL extends Application {
	static final SCRIPTS:Array<ScriptDef> = [
		{
			id: "Basic.hx",
			path: "./scripts/Basic.hx",
			context: [
				{fqName: "feathers.controls.Button", cls: Button},
				{fqName: "feathers.controls.Alert", cls: feathers.controls.Alert},
				{fqName: "feathers.controls.LayoutGroup", cls: LayoutGroup},
				{fqName: "feathers.events.TriggerEvent", cls: TriggerEvent}
			]
		},
		{
			id: "Bytecode.hxbc",
			path: "./scripts/Bytecode.hxbc",
			isBytecode: true,
		},
		{
			id: "Sandboxing.hx",
			path: "./scripts/Sandboxing.hx",
		},
		{
			id: "Million.hx",
			path: "./scripts/Million.hx",
		}
	];

	var lyt:HorizontalLayout;
	var scriptArea:ScriptArea;
	var executeButton:Button;
	var right:LayoutGroup;
	var dropdown:PopUpListView;
	var label:Label;
	var container:LayoutGroup;
	var selectedScript:ScriptDef;
	var selectedScriptContent:Bytes;

	public function new() {
		var theme = cast(Theme.fallbackTheme, IDarkModeTheme);
		theme.darkMode = true;

		super();
		init();
	}

	function init() {
		lyt = new HorizontalLayout();
		lyt.gap = 10;
		lyt.setPadding(10);
		this.layout = lyt;

		var left = new LayoutGroup();
		left.layoutData = new HorizontalLayoutData(100, 100);
		this.addChild(left);
		var leftLayout = new VerticalLayout();
		leftLayout.gap = 10;
		leftLayout.horizontalAlign = HorizontalAlign.CENTER;
		left.layout = leftLayout;

		dropdown = new PopUpListView();
		dropdown.dataProvider = new ArrayCollection(SCRIPTS);
		dropdown.layoutData = new VerticalLayoutData(100);
		dropdown.itemToText = function(item:Dynamic) {
			return item.id;
		};
		dropdown.addEventListener(Event.CHANGE, (event) -> {
			selectedScript = dropdown.selectedItem;
			loadScript();
		});
		left.addChild(dropdown);

		scriptArea = new ScriptArea();
		scriptArea.text = "";
		scriptArea.layoutData = new VerticalLayoutData(100, 100);
		left.addChild(scriptArea);

		executeButton = new Button();
		executeButton.text = "Execute Haxiom Script";
		executeButton.layoutData = new HorizontalLayoutData(100, 100);
		executeButton.addEventListener(TriggerEvent.TRIGGER, onExecuteTrigger);
		left.addChild(executeButton);

		right = new LayoutGroup();
		right.layoutData = new HorizontalLayoutData(100, 100);
		var rightLayout = new VerticalLayout();
		rightLayout.gap = 10;
		right.layout = rightLayout;
		this.addChild(right);

		label = new Label("Shared Container");
		right.addChild(label);

		container = new LayoutGroup();
		container.backgroundSkin = new RectangleSkin(FillStyle.SolidColor(0x181818), LineStyle.SolidColor(1, 0));
		container.layoutData = new VerticalLayoutData(100, 100);
		var containerLayout = new VerticalLayout();
		containerLayout.gap = 10;
		containerLayout.horizontalAlign = HorizontalAlign.CENTER;
		containerLayout.verticalAlign = VerticalAlign.MIDDLE;
		container.layout = containerLayout;
		right.addChild(container);

		selectedScript = SCRIPTS[0];
		loadScript();
		/*
			haxe.Timer.delay(function() {
				onExecuteTrigger(null);
			}, 500);
		 */
	}

	function registerFFI(haxiom:Haxiom) {
		FFI.registerClass(haxiom, "feathers.core.FeathersControl", FeathersControl);
		FFI.registerClass(haxiom, "feathers.controls.Button", Button);
		FFI.registerClass(haxiom, "feathers.controls.Alert", feathers.controls.Alert);
		FFI.registerClass(haxiom, "feathers.controls.Label", Label);
		FFI.registerClass(haxiom, "feathers.controls.LayoutGroup", LayoutGroup);
		FFI.registerClass(haxiom, "feathers.events.TriggerEvent", TriggerEvent);
	}

	function registerGlobals(haxiom:Haxiom) {
		haxiom.setGlobal("ScriptContext", {
			container: container,
			sandboxedContainer: {
				addChild: function(child:FeathersControl) {
					container.addChild(child); // Forwards call to native container
				}
			}
		});
	}

	function loadScript() {
		container.removeChildren();
		scriptArea.load(selectedScript);
	}

	function onExecuteTrigger(e:TriggerEvent) {
		container.removeChildren();
		trace("Executing script...");
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

			// Simulate button click to verify guest event listener
			/*
				if (container.numChildren > 0) {
					var child = container.getChildAt(0);
					if (Std.isOfType(child, Button)) {
						var btn:Button = cast child;
						trace("Dynamically triggering button click event...");
						TriggerEvent.dispatchFromMouseEvent(btn, new MouseEvent(MouseEvent.CLICK));
						trace("Button click event dispatched successfully!");
					}
				}
			 */
		} catch (err:Dynamic) {
			trace("CATCH ERROR: " + err);
			trace("CATCH STACK: " + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		final d = (Timer.stamp() - t);
		if (d < 1) {
			trace("Script executed in " + (d * 1000) + " milliseconds");
		} else {
			trace("Script executed in " + d + " seconds");
		}
	}
}

typedef ScriptDef = {
	id:String,
	path:String,
	?isBytecode:Bool,
	?context:Array<ScriptContext>,
}

typedef ScriptContext = {
	fqName:String,
	cls:Class<Dynamic>,
}
