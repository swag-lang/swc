#global private

func(T) arranged(
    item00: T, item01: s32, item02: s32, item03: s32, item04: s32,
    item05: s32, item06: s32, item07: s32, item08: s32, item09: s32,
    item10: s32, item11: s32, item12: s32, item13: s32, item14: s32,
    item15: s32, item16: s32, item17: s32, item18: s32, item19: s32)->bool
{
    return item00 == 0 and item01 == 1 and item02 == 2 and item03 == 3 and item04 == 4
        and item05 == 5 and item06 == 6 and item07 == 7 and item08 == 8 and item09 == 9
        and item10 == 10 and item11 == 11 and item12 == 12 and item13 == 13 and item14 == 14
        and item15 == 15 and item16 == 16 and item17 == 17 and item18 == 18 and item19 == 19
}

#test
{
    // Reversed names exercise both the initial scans and the promoted parameter index.
    Swag.assert(arranged(0's32,
        item19: 19's32, item18: 18, item17: 17, item16: 16, item15: 15,
        item14: 14, item13: 13, item12: 12, item11: 11, item10: 10,
        item09: 9, item08: 8, item07: 7, item06: 6, item05: 5,
        item04: 4, item03: 3, item02: 2, item01: 1))
}

#test
{
    // UFCS excludes the receiver slot while positional arguments precede the named tail.
    let receiver = 0's32
    Swag.assert(receiver.arranged(1, 2,
        item19: 19, item18: 18, item17: 17, item16: 16, item15: 15,
        item14: 14, item13: 13, item12: 12, item11: 11, item10: 10,
        item09: 9, item08: 8, item07: 7, item06: 6, item05: 5,
        item04: 4, item03: 3))
}
