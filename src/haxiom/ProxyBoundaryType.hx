package haxiom;

@:noCompletion
final class ProxyBoundaryType {
	public final kind:String;
	public final nullable:Bool;
	public final element:ProxyBoundaryType;
	public final fields:Array<ProxyBoundaryField>;

	public function new(kind:String, ?nullable:Bool = false, ?element:ProxyBoundaryType, ?fields:Array<ProxyBoundaryField>) {
		this.kind = kind;
		this.nullable = nullable;
		this.element = element;
		this.fields = fields;
	}
}

@:noCompletion
final class ProxyBoundaryField {
	public final name:String;
	public final type:ProxyBoundaryType;
	public final optional:Bool;

	public function new(name:String, type:ProxyBoundaryType, ?optional:Bool = false) {
		this.name = name;
		this.type = type;
		this.optional = optional;
	}
}
