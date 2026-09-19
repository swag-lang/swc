#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func add16(a, b, c, flag: u16)->u16 => flag != 0 ? a + b : a + c
#[Swag.NoInline]
func sub16(a, b, c, flag: u16)->u16 => flag != 0 ? a - b : a - c
#[Swag.NoInline]
func xor16(a, b, c, flag: u16)->u16 => flag != 0 ? a ^ b : a ^ c
#[Swag.NoInline]
func and16(a, b, c, flag: u16)->u16 => flag != 0 ? a & b : a & c
#[Swag.NoInline]
func or16(a, b, c, flag: u16)->u16 => flag != 0 ? a | b : a | c
#[Swag.NoInline]
func mul16(a, b, c, flag: u16)->u16 => flag != 0 ? a * b : a * c

#test
{
    let values = [0'u16, 1, 7, 0x7FFF, 0x8000, 0xFFFF]
    for a in values do for b in values do for c in values do for flag in values
                {
                    let selected = flag != 0 ? b : c
                    Swag.assert(add16(a, b, c, flag) == a + selected)
                    Swag.assert(sub16(a, b, c, flag) == a - selected)
                    Swag.assert(xor16(a, b, c, flag) == (a ^ selected))
                    Swag.assert(and16(a, b, c, flag) == (a & selected))
                    Swag.assert(or16(a, b, c, flag) == (a | selected))
                    Swag.assert(mul16(a, b, c, flag) == a * selected)
                }
}
