#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesThree(a: u64)->u64 => a * 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesFive(a: u64)->u64 => a * 5

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesNine(a: u64)->u64 => a * 9

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func scaledSum(a, b: u64)->u64 => (a << 3) + b

#[Swag.NoInline]
func indexed(values: [*]u64, index: u64)->u64 => values[index]

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sharedInput(a, b: u64)->u64 => (a * 5 + b) ^ a

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000]
    for a in values
    {
        Swag.assert(timesThree(a) == ((a << 1) + a))
        Swag.assert(timesFive(a) == ((a << 2) + a))
        Swag.assert(timesNine(a) == ((a << 3) + a))
        for b in values
        {
            Swag.assert(scaledSum(a, b) == (b + a * 8))
            Swag.assert(sharedInput(a, b) == ((((a << 2) + a) + b) ^ a))
        }
    }
    var array = [11'u64, 27, 49, 83]
    for i in 4'u64 do
        Swag.assert(indexed(&array[0], i) == array[i])
}
