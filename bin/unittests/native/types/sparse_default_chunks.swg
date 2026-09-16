#global private

struct FourChunks
{
    head:   u64 = 0xFEDCBA9876543210
    zerosA: [1023] u64
    middle: u64 = 0x0102030405060708
    zerosB: [1023] u64
    tail:   u64 = 0x8877665544332211
    last:   u64 = 0x123456789ABCDEF0
}

struct FiveChunks
{
    using base: FourChunks
    extra:      u64 = 0x1020304050607080
}

#[Swag.NoInline]
func checkFour(value: const *FourChunks)
{
    Swag.assert(value.head == 0xFEDCBA9876543210)
    Swag.assert(value.middle == 0x0102030405060708)
    Swag.assert(value.tail == 0x8877665544332211)
    Swag.assert(value.last == 0x123456789ABCDEF0)
    for element in value.zerosA do Swag.assert(element == 0)
    for element in value.zerosB do Swag.assert(element == 0)
}

// Four nonzero chunks use sparse stores; the fifth selects the fallback.
#test
{
    var sparse: FourChunks
    checkFour(&sparse)

    var dense: FiveChunks
    checkFour(&dense.base)
    Swag.assert(dense.extra == 0x1020304050607080)
}
