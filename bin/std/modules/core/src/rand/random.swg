#global namespace Random

#[Swag.Tls]
fileprivate var g_SharedRng: Rng'MWC

// Get the default per thread random generator
public func shared()->*Rng'MWC => &g_SharedRng
