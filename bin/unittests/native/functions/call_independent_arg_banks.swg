#global private

#[Swag.NoInline]
func sumRegisterBanks(
    i0: s64, f0: f64, i1: s64, f1: f64,
    i2: s64, f2: f64, i3: s64, f3: f64,
    i4: s64, f4: f64, i5: s64, f5: f64)->s64
{
    return i0 + i1 + i2 + i3 + i4 + i5 + cast(s64, (f0 + f1 + f2 + f3 + f4 + f5))
}

#[Swag.NoInline]
func sumSpilledBanks(
    i0: s64, f0: f64, i1: s64, f1: f64,
    i2: s64, f2: f64, i3: s64, f3: f64,
    i4: s64, f4: f64, i5: s64, f5: f64,
    i6: s64, f6: f64)->s64
{
    return sumRegisterBanks(i0, f0, i1, f1, i2, f2, i3, f3, i4, f4, i5, f5) + i6 + cast(s64, f6)
}

alias RegisterBankFn = func(s64, f64, s64, f64, s64, f64, s64, f64, s64, f64, s64, f64)->s64

#[Swag.NoInline]
func sumEightBanks(
    i0: s64, f0: f64, i1: s64, f1: f64,
    i2: s64, f2: f64, i3: s64, f3: f64,
    i4: s64, f4: f64, i5: s64, f5: f64,
    i6: s64, f6: f64, i7: s64, f7: f64)->s64
{
    return i0 + i1 + i2 + i3 + i4 + i5 + i6 + i7 + cast(s64, (f0 + f1 + f2 + f3 + f4 + f5 + f6 + f7))
}

#[Swag.NoInline]
func repeatEightBanks(count: u32)->s64
{
    var total = 0's64
    for i in count
    {
        let value = cast(s64, i)
        total += sumEightBanks(value, 1, value, 2, value, 3, value, 4, value, 5, value, 6, value, 7, value, 8)
    }
    return total
}

#test
{
    Swag.assert(sumRegisterBanks(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12) == 78)
    Swag.assert(sumSpilledBanks(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14) == 105)

    let fn: RegisterBankFn = &sumRegisterBanks
    Swag.assert(fn(12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1) == 78)
    Swag.assert(repeatEightBanks(0) == 0)
    Swag.assert(repeatEightBanks(64) == 18432)

    var changing = 0's64
    for i in 8
    {
        let value = cast(s64, i)
        changing += sumRegisterBanks(value, cast(f64, value), value, 2, value, 3, value, 4, value, 5, value, 6)
    }
    Swag.assert(changing == 356)
}
