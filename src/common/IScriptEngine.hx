package common;

/**
 * Standard interface for embeddable scripting hosts.
 */
interface IScriptEngine {
    /**
     * Interpret the given script source code and return the result.
     */
    function interpret<T>(source:String, ?onDone:T->Void, ?staticTypes:Bool = false):T;

    /**
     * Register a global variable or utility in the scripting environment.
     */
    function setGlobal(name:String, value:Dynamic):Void;
}
