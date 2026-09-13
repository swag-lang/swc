#global private

enum FirstKind: u8 { A, B }
enum SecondKind: u16 { C, D }

struct Wide
{
    #static if false
    {
        field32: u64
    }

    f00, f01, f02, f03, f04, f05, f06, f07: FirstKind
    f08, f09, f10, f11, f12, f13, f14, f15: FirstKind
    f16, f17, f18, f19, f20, f21, f22, f23: FirstKind
    f24, f25, f26, f27, f28, f29, f30, f31: FirstKind
    field32:                                FirstKind
    last:                                   SecondKind
}

struct Mixed
{
    first:  FirstKind
    second: SecondKind
    third:  FirstKind
}

#[Swag.Inline]
func wideScore(value: Wide)->u32
{
    #assert(#typeof(value.field32) == FirstKind)
    #assert(#typeof(value.last) == SecondKind)
    return cast(u32) value.f00 + cast(u32) value.f16 * 10 + cast(u32) value.field32 * 100 + cast(u32) value.last * 1000
}

#test
{
    let value: Wide = {
        last: .D, field32: .B, f31: .A, f30: .A, f29: .A, f28: .A, f27: .A,
        f26: .A, f25: .A, f24: .A, f23: .A, f22: .A, f21: .A, f20: .A,
        f19: .A, f18: .A, f17: .A, f16: .B, f15: .A, f14: .A, f13: .A,
        f12: .A, f11: .A, f10: .A, f09: .A, f08: .A, f07: .A, f06: .A,
        f05: .A, f04: .A, f03: .A, f02: .A, f01: .A, f00: .B
        }
    Swag.assert(wideScore(value) == 1111)

    let sparse = Wide{last: .D, field32: .B}
    Swag.assert(wideScore(sparse) == 1100)
}

#test
{
    // Named arguments keep their slots after a positional prefix, even out of order.
    let value: Mixed = {.B, third: .A, second: .D}
    Swag.assert(value.first == .B)
    Swag.assert(value.second == .D)
    Swag.assert(value.third == .A)
}
