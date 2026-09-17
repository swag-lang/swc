#global private
using Swag

// A value loaded only to be the left side of a register compare is compared
// in memory. Every width, signed and unsigned orders, and a load whose right
// side is itself loaded must keep the source answers.

struct Stamp
{
    year:  u16
    month: u8
    day:   s8
    ticks: s32
    size:  u64
}

#[Swag.Optimize(true), Swag.NoInline]
func same(a, b: const *Stamp)->bool => a.year == b.year and a.month == b.month and a.day == b.day and a.ticks == b.ticks and a.size == b.size

#[Swag.Optimize(true), Swag.NoInline]
func earlierDay(a: const *Stamp, day: s8)->bool => a.day < day

#[Swag.Optimize(true), Swag.NoInline]
func biggerThan(a: const *Stamp, size: u64)->bool => a.size > size

#[Swag.Optimize(true), Swag.NoInline]
func ticksBelow(a: const *Stamp, t: s32)->s32 => a.ticks <= t ? 1 : 2

#test
{
    var a: Stamp = {year: 2026, month: 9, day: -3, ticks: -100, size: 0x8000000000000001}
    var b = a
    Swag.assert(same(&a, &b))
    b.day = 4
    Swag.assert(not same(&a, &b))
    b = a
    b.size += 1
    Swag.assert(not same(&a, &b))

    Swag.assert(earlierDay(&a, 0))
    Swag.assert(not earlierDay(&a, -5))
    Swag.assert(biggerThan(&a, 5))
    Swag.assert(not biggerThan(&a, 0xFFFFFFFFFFFFFFFF))
    Swag.assert(ticksBelow(&a, -100) == 1)
    Swag.assert(ticksBelow(&a, -101) == 2)
}
