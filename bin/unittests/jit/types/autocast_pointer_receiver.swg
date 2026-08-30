#global private

// 'cast()' is explicit, but it takes its destination from the context instead of naming it.
// An integer only becomes an address through a cast that writes the destination down: letting
// a deduced one do it makes a plain integer bindable to a pointer parameter, and overload
// resolution then hands the first written argument to the receiver of a method call, silently
// shifting every argument by one.

struct AutoCastLimits
{
    lo:  u64
    hi:  u64
    tag: u64
}

impl AutoCastLimits
{
    const MinSize = 16
    const MaxSize = 4096

    mtd setRange(min = 0'u64, max = Swag.U64.Max)
    {
        .lo  = min
        .hi  = max
        .tag = 7
    }
}

var AutoCastStorage: AutoCastLimits

#test
{
    let limits = &AutoCastStorage
    limits.setRange(cast() AutoCastLimits.MinSize, cast() AutoCastLimits.MaxSize)
    Swag.assert(AutoCastStorage.lo == 16)
    Swag.assert(AutoCastStorage.hi == 4096)
    Swag.assert(AutoCastStorage.tag == 7)
}

#test
{
    // The written spellings keep converting an integer to an address in one step.
    var storage: [8] u8
    let base = storage.buffer
    Swag.assert(cast([*] u8) cast(u64) base == base)
    Swag.assert(cast(*void) 16'u8 == cast(*void) 16'u64)

    // A deduced destination still converts between integers, and still reaches a pointer
    // from the one integer type that is exactly an address.
    var wide: u64 = 0
    wide = cast() AutoCastLimits.MinSize
    Swag.assert(wide == 16)

    var deduced: [*] u8 = cast() cast(u64) base
    Swag.assert(deduced == base)
}
