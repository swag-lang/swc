#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func add32(a, b, c, flag: u32)->u32 => flag != 0 ? a + b : a + c
#[Swag.NoInline]
func sub32(a, b, c, flag: u32)->u32 => flag != 0 ? a - b : a - c
#[Swag.NoInline]
func xor32(a, b, c, flag: u32)->u32 => flag != 0 ? a ^ b : a ^ c
#[Swag.NoInline]
func and32(a, b, c, flag: u32)->u32 => flag != 0 ? a & b : a & c
#[Swag.NoInline]
func or32(a, b, c, flag: u32)->u32 => flag != 0 ? a | b : a | c
#[Swag.NoInline]
func mul32(a, b, c, flag: u32)->u32 => flag != 0 ? a * b : a * c
#[Swag.NoInline]
func add64(a, b, c, flag: u64)->u64 => flag != 0 ? a + b : a + c
#[Swag.NoInline]
func sub64(a, b, c, flag: u64)->u64 => flag != 0 ? a - b : a - c
#[Swag.NoInline]
func xor64(a, b, c, flag: u64)->u64 => flag != 0 ? a ^ b : a ^ c
#[Swag.NoInline]
func and64(a, b, c, flag: u64)->u64 => flag != 0 ? a & b : a & c
#[Swag.NoInline]
func or64(a, b, c, flag: u64)->u64 => flag != 0 ? a | b : a | c
#[Swag.NoInline]
func mul64(a, b, c, flag: u64)->u64 => flag != 0 ? a * b : a * c

#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values do for b in values do for c in values do for flag in values
                {
                    let selected = flag != 0 ? b : c
                    Swag.require(add64(a, b, c, flag) == a + selected)
                    Swag.require(sub64(a, b, c, flag) == a - selected)
                    Swag.require(xor64(a, b, c, flag) == (a ^ selected))
                    Swag.require(and64(a, b, c, flag) == (a & selected))
                    Swag.require(or64(a, b, c, flag) == (a | selected))
                    Swag.require(mul64(a, b, c, flag) == a * selected)

                    let a32        = cast(u32, a)
                    let b32        = cast(u32, b)
                    let c32        = cast(u32, c)
                    let flag32     = cast(u32, flag)
                    let selected32 = flag32 != 0 ? b32 : c32
                    Swag.require(add32(a32, b32, c32, flag32) == a32 + selected32)
                    Swag.require(sub32(a32, b32, c32, flag32) == a32 - selected32)
                    Swag.require(xor32(a32, b32, c32, flag32) == (a32 ^ selected32))
                    Swag.require(and32(a32, b32, c32, flag32) == (a32 & selected32))
                    Swag.require(or32(a32, b32, c32, flag32) == (a32 | selected32))
                    Swag.require(mul32(a32, b32, c32, flag32) == a32 * selected32)
                }
}
