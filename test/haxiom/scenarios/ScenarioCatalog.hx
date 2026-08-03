package haxiom.scenarios;

import haxe.io.Bytes;

class ScenarioCatalog {
	public static function all():Array<ScenarioDefinition> {
		return [
			commerce(),
			workflow(),
			inventory(),
			dataPipeline(),
			resourcePipeline(),
			vmStress()
		];
	}

	static function commerce():ScenarioDefinition {
		return {
			name: "commerce-order-processing",
			moduleName: "CommerceScenario",
			expected: "6697|1004|5693|4300|2397|quantity",
			configure: engine -> engine.registerClass("ScenarioHostPricing", ScenarioHostPricing),
			source: '
				extern class ScenarioHostPricing {
					static function discountRate(tier:String, total:Int):Int;
					static function shippingFor(total:Int):Int;
				}

				class OrderLine {
					public var sku:String;
					public var category:String;
					public var unitPrice:Int;
					public var quantity:Int;

					public function new(sku:String, category:String, unitPrice:Int, quantity:Int) {
						if (quantity <= 0) {
							throw "quantity";
						}
						this.sku = sku;
						this.category = category;
						this.unitPrice = unitPrice;
						this.quantity = quantity;
					}

					public function subtotal():Int {
						return unitPrice * quantity;
					}
				}

				class ShoppingCart {
					var tier:String;
					var lines:Array<OrderLine>;

					public function new(tier:String) {
						this.tier = tier;
						this.lines = [];
					}

					public function add(line:OrderLine):Void {
						lines.push(line);
					}

					public function summarize():String {
						var subtotal = 0;
						var categories = new Map<String, Int>();
						for (line in lines) {
							var lineTotal = line.subtotal();
							subtotal += lineTotal;
							var current = categories.exists(line.category) ? categories.get(line.category) : 0;
							categories.set(line.category, current + lineTotal);
						}

						var rate = ScenarioHostPricing.discountRate(tier, subtotal);
						var discount = Std.int(subtotal * rate / 100);
						var shipping = ScenarioHostPricing.shippingFor(subtotal);
						var finalTotal = subtotal - discount + shipping;
						return subtotal + "|" + discount + "|" + finalTotal + "|"
							+ categories.get("books") + "|" + categories.get("games");
					}
				}

				class CommerceScenario {
					static public function main():String {
						var cart = new ShoppingCart("gold");
						cart.add(new OrderLine("HX-01", "books", 1250, 2));
						cart.add(new OrderLine("VM-02", "games", 799, 3));
						cart.add(new OrderLine("BC-03", "books", 450, 4));

						var rejected = "none";
						try {
							cart.add(new OrderLine("BAD", "books", 100, 0));
						} catch (error:Dynamic) {
							rejected = Std.string(error);
						}
						return cart.summarize() + "|" + rejected;
					}
				}
			'
		};
	}

	static function workflow():ScenarioDefinition {
		return {
			name: "stateful-workflow",
			moduleName: "WorkflowScenario",
			expected: "completed:done|pending>running>progress:3>paused:maintenance>running>completed:done|5|closed",
			source: '
				enum WorkflowState {
					Pending;
					Running;
					Paused(reason:String);
					Completed(summary:String);
				}

				class Workflow {
					var state:WorkflowState;
					var history:Array<String>;
					var listeners:Array<String->Void>;

					public function new() {
						state = Pending;
						history = ["pending"];
						listeners = [];
					}

					public function onChange(listener:String->Void):Void {
						listeners.push(listener);
					}

					function record(event:String):Void {
						history.push(event);
						for (listener in listeners) {
							listener(event);
						}
					}

					public function start():Void {
						switch (state) {
							case Pending:
								state = Running;
								record("running");
							default:
								throw "cannot start";
						}
					}

					public function advance(amount:Int):Void {
						switch (state) {
							case Running: record("progress:" + amount);
							default: throw "cannot advance";
						}
					}

					public function pause(reason:String):Void {
						switch (state) {
							case Running:
								state = Paused(reason);
								record("paused:" + reason);
							default: throw "cannot pause";
						}
					}

					public function resume():Void {
						switch (state) {
							case Paused(_):
								state = Running;
								record("running");
							default: throw "closed";
						}
					}

					public function complete(summary:String):Void {
						switch (state) {
							case Running:
								state = Completed(summary);
								record("completed:" + summary);
							default: throw "cannot complete";
						}
					}

					public function label():String {
						return switch (state) {
							case Pending: "pending";
							case Running: "running";
							case Paused(reason): "paused:" + reason;
							case Completed(summary): "completed:" + summary;
						};
					}

					public function journal():String {
						return history.join(">");
					}
				}

				class WorkflowScenario {
					static public function main():String {
						var workflow = new Workflow();
						var eventCount = 0;
						workflow.onChange(function(event:String):Void {
							eventCount++;
						});
						workflow.start();
						workflow.advance(3);
						workflow.pause("maintenance");
						workflow.resume();
						workflow.complete("done");

						var rejected = "none";
						try {
							workflow.resume();
						} catch (error:Dynamic) {
							rejected = Std.string(error);
						}
						return workflow.label() + "|" + workflow.journal() + "|" + eventCount + "|" + rejected;
					}
				}
			'
		};
	}

	static function inventory():ScenarioDefinition {
		return {
			name: "inventory-object-model",
			moduleName: "InventoryScenario",
			expected: "1,2,3|3500|0|bundle:2",
			source: '
				interface Priceable {
					function price():Int;
				}

				class InventoryItem implements Priceable {
					static var nextId:Int = 1;
					public var id(default, null):Int;
					public var stock(default, set):Int;
					var basePrice:Int;

					public function new(basePrice:Int, stock:Int) {
						id = nextId++;
						this.basePrice = basePrice;
						this.stock = stock;
					}

					function set_stock(value:Int):Int {
						stock = value < 0 ? 0 : value;
						return stock;
					}

					public function price():Int {
						return basePrice;
					}
				}

				class BookItem extends InventoryItem {
					var markdown:Int;

					public function new(price:Int, stock:Int, markdown:Int) {
						super(price, stock);
						this.markdown = markdown;
					}

					override public function price():Int {
						return Std.int(super.price() * (100 - markdown) / 100);
					}
				}

				class BundleItem extends InventoryItem {
					var items:Array<Priceable>;

					public function new(items:Array<Priceable>) {
						super(0, 1);
						this.items = items;
					}

					override public function price():Int {
						var total = 100;
						for (item in items) {
							total += item.price();
						}
						return total;
					}

					public function description():String {
						return "bundle:" + items.length;
					}
				}

				class InventoryScenario {
					static public function main():String {
						var first = new BookItem(1200, 4, 25);
						var second = new BookItem(800, 2, 0);
						var bundle = new BundleItem([first, second]);
						var products:Array<Priceable> = [first, second, bundle];
						var total = 0;
						for (product in products) {
							total += product.price();
						}
						first.stock = -3;
						return first.id + "," + second.id + "," + bundle.id + "|" + total + "|"
							+ first.stock + "|" + bundle.description();
					}
				}
			'
		};
	}

	static function dataPipeline():ScenarioDefinition {
		return {
			name: "json-data-pipeline",
			moduleName: "DataPipelineScenario",
			expected: "Carol:21,Alice:20,Dave:18|eu:41|apac:18|4",
			source: '
				class DataPipelineScenario {
					static function score(record:Dynamic):Int {
						var total = 0;
						for (value in (record.scores:Array<Int>)) {
							total += value;
						}
						return total;
					}

					static public function main():String {
						var payload = {
							records: [
								{name: "Alice", region: "eu", scores: [8, 12], meta: {enabled: true}},
								{name: "Bob", region: "us", scores: [5, 7], meta: {enabled: false}},
								{name: "Carol", region: "eu", scores: [20, 1], meta: null},
								{name: "Dave", region: "apac", scores: [9, 9], meta: {enabled: true}}
							]
						};
						var encoded = haxe.Json.stringify(payload);
						var decoded:Dynamic = haxe.Json.parse(encoded);
						var records:Array<Dynamic> = cast decoded.records;
						var accepted = records.filter(function(record) {
							var enabled = record.meta?.enabled ?? true;
							return enabled && ~/^[ACD]/.match(record.name);
						});
						accepted.sort(function(left, right) {
							return score(right) - score(left);
						});

						var regions = new Map<String, Int>();
						var labels = [];
						for (record in accepted) {
							var value = score(record);
							labels.push(record.name + ":" + value);
							var current = regions.exists(record.region) ? regions.get(record.region) : 0;
							regions.set(record.region, current + value);
						}
						return labels.join(",") + "|eu:" + regions.get("eu") + "|apac:"
							+ regions.get("apac") + "|" + records.length;
					}
				}
			'
		};
	}

	static function vmStress():ScenarioDefinition {
		return {
			name: "vm-control-flow-stress",
			moduleName: "VMStressScenario",
			expected: "50005000|false|500500|5000|500|42|boom|191949|377986|946",
			vmOnly: true,
			source: '
					class RecursiveWorker {
						public function new() {}

						public function descend(n:Int, count:Int):Int {
							return n == 0 ? count : descend(n - 1, count + 1);
						}
					}

					class VMStressScenario {
					static function tail(n:Int, acc:Int):Int {
						return n == 0 ? acc : tail(n - 1, acc + n);
					}

					static function isEven(n:Int):Bool {
						return n == 0 ? true : isOdd(n - 1);
					}

					static function isOdd(n:Int):Bool {
						return n == 0 ? false : isEven(n - 1);
					}

					static function nonTail(n:Int):Int {
						return n == 0 ? 0 : n + nonTail(n - 1);
					}

					static function accumulator(base:Int):Int->Int {
						var total = 0;
						return function(value:Int):Int {
							total += base + value;
							return total;
						};
					}

					static function risky(depth:Int):Void {
						if (depth == 0) {
							throw "boom";
						}
						risky(depth - 1);
					}

					static public function main():String {
						function closureDepth(n:Int):Int {
							return n == 0 ? 0 : 1 + closureDepth(n - 1);
						}

						var worker = new RecursiveWorker();
						var add = accumulator(11);
						add(4);
						add(8);
						var closureTotal = add(-3);

						var caught = "none";
						try {
							risky(250);
						} catch (error:Dynamic) {
							caught = Std.string(error);
						}

						var loopTotal = 0;
						for (i in 0...4000) {
							loopTotal += (i * 31) % 97;
						}

						var squares = [for (i in 0...200) i * i];
						var squareTotal = 0;
						for (value in squares.filter(function(value) return value % 7 == 0)) {
							squareTotal += value;
						}

						var lookup = new Map<Int, Int>();
						for (i in 0...60) {
							lookup.set(i, (i * 13) % 101);
						}
						var mapTotal = 0;
						var index = 0;
						while (index < 60) {
							mapTotal += lookup.get(index);
							index += 3;
						}

						return tail(10000, 0) + "|" + isEven(10001) + "|" + nonTail(1000) + "|" + worker.descend(5000, 0)
							+ "|" + closureDepth(500) + "|" + closureTotal + "|" + caught
							+ "|" + loopTotal + "|" + squareTotal + "|" + mapTotal;
					}
				}
			'
		};
	}

	static function resourcePipeline():ScenarioDefinition {
		return {
			name: "embedded-resource-pipeline",
			moduleName: "ResourcePipelineScenario",
			expected: "scenario-pack|3|8|967|0|255",
			configure: configureResources,
			source: '
				import haxe.io.Bytes;

				class ScenarioAssetPack {
					@:haxiom.resource("scenario/config.json")
					public var configText:String;

					@:haxiom.resource("scenario/payload.bin")
					public var payload:Bytes;

					public function new() {}

					public function checksum():Int {
						var total = 0;
						for (i in 0...payload.length) {
							total += payload.get(i);
						}
						return total;
					}
				}

				class ResourcePipelineScenario {
					static public function main():String {
						var assets = new ScenarioAssetPack();
						var config:Dynamic = haxe.Json.parse(assets.configText);
						return config.name + "|" + config.version + "|" + assets.payload.length + "|"
							+ assets.checksum() + "|" + assets.payload.get(0) + "|" + assets.payload.get(7);
					}
				}
			'
		};
	}

	static function configureResources(engine:Haxiom):Void {
		engine.addResource("scenario/config.json", Bytes.ofString('{"name":"scenario-pack","version":3}'));
		var payload = Bytes.alloc(8);
		var values = [0, 1, 2, 127, 128, 200, 254, 255];
		for (i in 0...values.length) {
			payload.set(i, values[i]);
		}
		engine.addResource("scenario/payload.bin", payload);
	}
}
