package haxiom;

/**
 * Encapsulates instance-bound FFI lookup tables, exposed abstracts/generics/modules,
 * native static fields, and member resolver/assigner callbacks for a Haxiom engine instance.
 * Package-private to `haxiom` (@:allow(haxiom)) to prevent public API exposure.
 */
@:allow(haxiom)
class FFIRegistry {
	var exposedAbstracts = new Map<String, {implClass:String, methods:Array<String>, underlying:String}>();
	var exposedGenerics = new Map<String, String>();
	var abstractImpls = new Map<String, Dynamic>();
	var exposedModules = new Map<String, Array<String>>();
	var memberResolvers:Array<(obj:Dynamic, field:String) -> Dynamic> = [];
	var memberAssigners:Array<(obj:Dynamic, field:String, val:Dynamic) -> Bool> = [];
	var nativeStaticFields = new Map<String, Map<String, Dynamic>>();

	function new() {}

	function registerMemberResolver(resolver:(obj:Dynamic, field:String) -> Dynamic):Void {
		memberResolvers.push(resolver);
	}

	function registerMemberAssigner(assigner:(obj:Dynamic, field:String, val:Dynamic) -> Bool):Void {
		memberAssigners.push(assigner);
	}

	function registerStaticField(className:String, fieldName:String, value:Dynamic):Void {
		var fields = nativeStaticFields.get(className);
		if (fields == null) {
			fields = new Map<String, Dynamic>();
			nativeStaticFields.set(className, fields);
		}
		fields.set(fieldName, value);
	}
}
