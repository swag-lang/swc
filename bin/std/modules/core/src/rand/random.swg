#global namespace Random

tls private var g_SharedGenerator: Generator'MultiplyWithCarry32

// Returns the default generator for the current thread.
//
// Each thread owns its generator, so calls do not race against another thread's. An unseeded
// generator seeds itself from the clock and thread ID on its first draw. Seed it explicitly when
// the sequence must be reproducible.
public func shared()->*Generator'MultiplyWithCarry32 => &g_SharedGenerator
