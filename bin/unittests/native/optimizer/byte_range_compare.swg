#global private

// Range tests of a byte promoted to 32 bits compare the byte itself. Every
// byte value, ranges touching 0 and 255, and branch and value forms must keep
// their answers.

#[Swag.Optimize(true), Swag.NoInline]
func isUpper(c: u8)->bool => c >= 'A' and c <= 'Z'

#[Swag.Optimize(true), Swag.NoInline]
func isDigit(c: u8)->bool => c >= '0' and c <= '9'

#[Swag.Optimize(true), Swag.NoInline]
func isHigh(c: u8)->bool => c >= 200 and c <= 255

#[Swag.Optimize(true), Swag.NoInline]
func isLow(c: u8)->bool => c <= 31

#[Swag.Optimize(true), Swag.NoInline]
func countUpper(text: const [..] u8)->u32
{
    var count = 0'u32
    for c in text
    {
        if c >= 'A' and c <= 'Z' do
            count += 1
    }
    return count
}

func within(v, lo, hi: u32)->bool => v >= lo and v <= hi

#test
{
    var all: [256] u8
    for v in 0 until 256
    {
        let c = cast(u8) v
        all[v] = c
        let u = cast(u32) v
        Swag.assert(isUpper(c) == within(u, 65, 90))
        Swag.assert(isDigit(c) == within(u, 48, 57))
        Swag.assert(isHigh(c) == within(u, 200, 255))
        Swag.assert(isLow(c) == within(u, 0, 31))
    }

    Swag.assert(countUpper(all) == 26)
    Swag.assert(countUpper("Hello World, ABC xyz Z@[") == 6)
}
