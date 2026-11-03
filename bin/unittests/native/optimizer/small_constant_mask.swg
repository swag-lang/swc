#global private

#[Swag.NoInline]
func seven(a, b: u64)->u64 => a < b ? 7 : 0
#[Swag.NoInline]
func thirteen(a, b: u64)->u64 => a < b ? 13 : 0
#[Swag.NoInline]
func negative(a, b: u64)->s64 => a < b ? -7 : 0
#[Swag.NoInline]
func reverse(a, b: u64)->u64 => a < b ? 0 : 127
#[Swag.NoInline]
func equal(a, b: u64)->u64 => a == b ? 11 : 0
#[Swag.NoInline]
func signed(a, b: s64)->s64 => a < b ? 15 : 0
#[Swag.NoInline]
func narrow(a, b: u32)->u32 => a < b ? 7 : 0
#[Swag.NoInline]
func below(a, b: u64)->bool => a < b

#test
{
    let values = [0'u64, 1, 7, 127, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            if below(a, b)
            {
                Swag.require(seven(a, b) == 7)
                Swag.require(thirteen(a, b) == 13)
                Swag.require(negative(a, b) == -7)
                Swag.require(reverse(a, b) == 0)
            }
            else
            {
                Swag.require(seven(a, b) == 0)
                Swag.require(thirteen(a, b) == 0)
                Swag.require(negative(a, b) == 0)
                Swag.require(reverse(a, b) == 127)
            }
            Swag.require(equal(a, b) == (a == b ? 11'u64 : 0))
            let sa = cast #bit (s64, a)
            let sb = cast #bit (s64, b)
            Swag.require(signed(sa, sb) == (sa < sb ? 15's64 : 0))
            let na = cast(u32, (a & 0xFFFFFFFF))
            let nb = cast(u32, (b & 0xFFFFFFFF))
            Swag.require(narrow(na, nb) == (below(na, nb) ? 7'u32 : 0))
        }
    }
}
