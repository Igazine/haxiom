package haxiom;

typedef HXBCCompiledType = {
	var kind:String; // "package", "class", "interface", "enum", "abstract", "typedef"
	var name:String;
	var ?parent:String;
	var ?interfaces:Array<String>;
	var ?fieldCount:Int;
	var ?methodCount:Int;
	var ?methods:Array<String>;
	var ?constructorCount:Int;
	var ?constructors:Array<String>;
}

typedef HXBCDebugSymbol = {
	var slot:Int;
	var name:String;
	var startIp:Int;
	var endIp:Int;
}

typedef HXBCInfo = {
	var fileSize:Int;
	var uncompressedPayloadSize:Int;
	var compressionRatioPct:Float;
	var version:Int;
	var maxSlots:Int;
	var isAsync:Bool;
	var isEncrypted:Bool;
	var isCompressed:Bool;
	var checksum:String;
	var ?instructionCount:Int;
	var ?constantPoolSize:Int;
	var ?debugSymbolCount:Int;
	var ?positionMappingCount:Int;
	var ?debugSymbols:Array<HXBCDebugSymbol>;
	var ?sourceFiles:Array<String>;
	var ?compiledTypes:Array<HXBCCompiledType>;
	var ?embeddedResources:Array<{path:String, size:Int}>;
	var status:String; // "VALID", "ENCRYPTED", "CORRUPTED", "INVALID_MAGIC", "TOO_SHORT"
	var ?error:String;
}
