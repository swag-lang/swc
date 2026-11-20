#global private

// The first explicit conversion belongs to a method argument after the receiver.

struct CastLimits
{
    lo:  u64
    hi:  u64
    tag: u64
}

impl CastLimits
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

var CastLimitsStorage: CastLimits

#test
{
    let limits = &CastLimitsStorage
    limits.setRange(cast(u64, CastLimits.MinSize), cast(u64, CastLimits.MaxSize))
    Swag.require(CastLimitsStorage.lo == 16)
    Swag.require(CastLimitsStorage.hi == 4096)
    Swag.require(CastLimitsStorage.tag == 7)
}

#test
{
    var storage: [8] u8
    let base = storage.buffer
    let address = cast(u64, base)
    let restored = cast([*] u8, address)
    Swag.require(restored == base)
    Swag.require(cast(*void, 16'u8) == cast(*void, 16'u64))

    var wide: u64 = 0
    wide = cast(u64, CastLimits.MinSize)
    Swag.require(wide == 16)
}
