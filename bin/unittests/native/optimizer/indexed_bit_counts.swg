#global private

#[Swag.NoInline]
func nonzero(values: const [*]u64, index: u64)->u64 => Swag.countOnes(values[index])

#[Swag.NoInline]
func leading(values: const [*]u64, index: u64)->u64 => Swag.leadingZeros(values[index])

#[Swag.NoInline]
func trailing(values: const [*]u64, index: u64)->u64 => Swag.trailingZeros(values[index])

#[Swag.NoInline]
func narrowNonzero(values: const [*]u8, index: u64)->u8 => Swag.countOnes(values[index])

#[Swag.NoInline]
func narrowLeading(values: const [*]u8, index: u64)->u8 => Swag.leadingZeros(values[index])

#[Swag.NoInline]
func narrowTrailing(values: const [*]u8, index: u64)->u8 => Swag.trailingZeros(values[index])

#test
{
    let values    = [0_u64, 1, 0x8000000000000000, 0x0001000000000000, 0xF00000000000000F]
    let nonzeros  = [0_u64, 1, 1, 1, 8]
    let leadings  = [64_u64, 63, 0, 15, 0]
    let trailings = [64_u64, 0, 63, 48, 0]
    for _, index in values
    {
        Swag.require(nonzero(&values[0], index) == nonzeros[index])
        Swag.require(leading(&values[0], index) == leadings[index])
        Swag.require(trailing(&values[0], index) == trailings[index])
    }

    let narrowValues    = [0_u8, 1, 0x80, 0x10, 0xF3]
    let narrowNonzeros  = [0_u8, 1, 1, 1, 6]
    let narrowLeadings  = [8_u8, 7, 0, 3, 0]
    let narrowTrailings = [8_u8, 0, 7, 4, 0]
    for _, index in narrowValues
    {
        Swag.require(narrowNonzero(&narrowValues[0], index) == narrowNonzeros[index])
        Swag.require(narrowLeading(&narrowValues[0], index) == narrowLeadings[index])
        Swag.require(narrowTrailing(&narrowValues[0], index) == narrowTrailings[index])
    }
}
