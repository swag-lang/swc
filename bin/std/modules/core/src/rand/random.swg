#global namespace Random

#[Swag.Tls]
private var g_SharedGenerator: Generator'MultiplyWithCarry32

// Returns the default generator for the current thread.
public func shared()->*Generator'MultiplyWithCarry32 => &g_SharedGenerator
