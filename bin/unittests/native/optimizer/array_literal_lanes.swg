#global private
using Swag

// An array literal of runtime values assigned to a local whose address is
// handed out is built in a register, then copied whole. Every lane must carry
// its value, next to a path that sets only some elements of the same local.

struct Strengths
{
    bs: [4] u32
}

#[Swag.NoInline]
func weigh(strengths: const *Strengths)->u32 => strengths.bs[0] + strengths.bs[1] * 10 + strengths.bs[2] * 100 + strengths.bs[3] * 1000

#[Swag.Optimize(true), Swag.NoInline]
func spread(bs: u32, mixed: bool)->u32
{
    var strengths: Strengths
    if mixed
    {
        strengths.bs[0] = bs
        strengths.bs[2] = bs + 1
    }
    else
    {
        strengths.bs = [bs, bs, bs, bs]
    }

    return weigh(&strengths)
}

#[Swag.Optimize(true), Swag.NoInline]
func staggered(first, second: u32)->u32
{
    var strengths: Strengths
    strengths.bs = [first, second, first, second]
    return weigh(&strengths)
}

#test
{
    Swag.assert(spread(3, false) == 3333)
    Swag.assert(spread(2, true) == 302)
    Swag.assert(staggered(1, 2) == 2121)
    Swag.assert(staggered(7, 9) == 9797)
}
