package scenario.initializers;

class InvalidStaticInitializer {
	static var invalid:Dynamic = HaxiomHost.await(42);
}
