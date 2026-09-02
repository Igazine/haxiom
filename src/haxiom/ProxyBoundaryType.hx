package haxiom;

@:allow(haxiom)
@:allow(haxiom.proxies)
final class ProxyBoundaryType {
	private final kind:String;
	private final nullable:Bool;
	private final element:ProxyBoundaryType;
	private final fields:Array<ProxyBoundaryField>;

	private function new(kind:String, ?nullable:Bool = false, ?element:ProxyBoundaryType, ?fields:Array<ProxyBoundaryField>) {
		this.kind = kind;
		this.nullable = nullable;
		this.element = element;
		this.fields = fields;
	}
}

@:allow(haxiom)
@:allow(haxiom.proxies)
final class ProxyBoundaryField {
	private final name:String;
	private final type:ProxyBoundaryType;
	private final optional:Bool;

	private function new(name:String, type:ProxyBoundaryType, ?optional:Bool = false) {
		this.name = name;
		this.type = type;
		this.optional = optional;
	}
}
