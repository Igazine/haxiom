package haxiom;

/**
 * A platform-agnostic, lightweight Future/Promise class for async/await scripts.
 */
class Future {
    public var isCompleted(default, null):Bool = false;
    public var value(default, null):Dynamic = null;
    public var error(default, null):Dynamic = null;
    
    var callbacks:Array<Dynamic->Void> = [];
    var errorCallbacks:Array<Dynamic->Void> = [];

    public function new() {}

    /**
     * Registers callbacks to be invoked when the future completes or fails.
     */
    public function then(onResolve:Dynamic->Void, ?onReject:Dynamic->Void):Future {
        if (isCompleted) {
            if (error != null) {
                if (onReject != null) onReject(error);
            } else {
                onResolve(value);
            }
        } else {
            callbacks.push(onResolve);
            if (onReject != null) errorCallbacks.push(onReject);
        }
        return this;
    }

    /**
     * Resolves the future with a success value.
     */
    public function resolve(val:Dynamic):Void {
        if (isCompleted) return;
        isCompleted = true;
        value = val;
        var list = callbacks;
        callbacks = [];
        errorCallbacks = [];
        for (cb in list) cb(val);
    }

    /**
     * Rejects the future with an error.
     */
    public function reject(err:Dynamic):Void {
        if (isCompleted) return;
        isCompleted = true;
        error = err;
        var list = errorCallbacks;
        callbacks = [];
        errorCallbacks = [];
        for (cb in list) cb(err);
    }
}
