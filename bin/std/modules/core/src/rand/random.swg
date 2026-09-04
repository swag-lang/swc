#global namespace Random

    tls private var g_SharedGenerator: Generator'MultiplyWithCarry32

// Returns the default generator for the current thread.
//
// Each thread owns its generator, so no call is ever raced against another thread's. Each also
// starts from the same fixed state, which makes a single-threaded program reproducible and means
// two threads that never seed produce the same sequence. Seed it when the streams must differ.
public func shared()->*Generator'MultiplyWithCarry32 => &g_SharedGenerator
