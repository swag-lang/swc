#global private

#[Swag.NoInline]
func nonzero(values: const [*]u64, index: u64)->u64 => Swag.bitCountNz(values[index])

#[Swag.NoInline]
func leading(values: const [*]u64, index: u64)->u64 => Swag.bitCountLz(values[index])

#[Swag.NoInline]
func trailing(values: const [*]u64, index: u64)->u64 => Swag.bitCountTz(values[index])

#[Swag.NoInline]
func narrowNonzero(values: const [*]u8, index: u64)->u8 => Swag.bitCountNz(values[index])

#[Swag.NoInline]
func narrowLeading(values: const [*]u8, index: u64)->u8 => Swag.bitCountLz(values[index])

#[Swag.NoInline]
func narrowTrailing(values: const [*]u8, index: u64)->u8 => Swag.bitCountTz(values[index])

#test
{
    let values    = [0'u64, 1, 0x8000000000000000, 0x0001000000000000, 0xF00000000000000F]
    let nonzeros  = [0'u64, 1, 1, 1, 8]
    let leadings  = [64'u64, 63, 0, 15, 0]
    let trailings = [64'u64, 0, 63, 48, 0]
    for value, index in values
    {
        Swag.assert(nonzero(&values[0], index) == nonzeros[index])
        Swag.assert(leading(&values[0], index) == leadings[index])
        Swag.assert(trailing(&values[0], index) == trailings[index])
    }

    let narrowValues    = [0'u8, 1, 0x80, 0x10, 0xF3]
    let narrowNonzeros  = [0'u8, 1, 1, 1, 6]
    let narrowLeadings  = [8'u8, 7, 0, 3, 0]
    let narrowTrailings = [8'u8, 0, 7, 4, 0]
    for value, index in narrowValues
    {
        Swag.assert(narrowNonzero(&narrowValues[0], index) == narrowNonzeros[index])
        Swag.assert(narrowLeading(&narrowValues[0], index) == narrowLeadings[index])
        Swag.assert(narrowTrailing(&narrowValues[0], index) == narrowTrailings[index])
    }
}
