#global private

// A small left shift of a qword still read afterwards becomes an address
// computation. Shifts of one, two and three, values read again after the
// shift, shifts in place and dword shifts must all give the same results.

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func doubleAndMix(x: u64)->u64 => (x << 1) ^ x
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesFourPlus(x: u64)->u64 => (x << 2) + x
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesEightMinus(x: u64)->u64 => (x << 3) - x
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func inPlace(x: u64)->u64 => x << 3
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func narrow(x: u32)->u32 => (x << 3) ^ x
#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func shiftSum(p: const [*] u64, n: u64)->u64
{
    var total = 0'u64
    for i in n
    {
        let v = p[i]
        total += (v << 2) | v
    }
    return total
}

#[Swag.Optimize(false), Swag.NoInline, Swag.Safety(.Overflow, false)]
func slowShift(x: u64, k: u32)->u64 => x << k

#[Swag.Safety(.Overflow, false)]
#test
{
    for x in [0'u64, 1, 2, 7, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF, 0x123456789ABCDEF, 0x7FFFFFFFFFFFFFFF]
    {
        Swag.assert(doubleAndMix(x) == (slowShift(x, 1) ^ x))
        Swag.assert(timesFourPlus(x) == slowShift(x, 2) + x)
        Swag.assert(timesEightMinus(x) == slowShift(x, 3) - x)
        Swag.assert(inPlace(x) == slowShift(x, 3))
        let x32 = cast #wrap (u32) x
        Swag.assert(narrow(x32) == (cast #wrap (u32) slowShift(cast(u64) x32, 3) ^ x32))
    }

    var values: [3] u64 = [1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000001]
    var expected        = 0'u64
    for v in values do
        expected += slowShift(v, 2) | v
    Swag.assert(shiftSum(&values[0], 3) == expected)
}
