#global private

#[Swag.Strict]
alias VariadicStrictAny = any

struct VariadicAnyBox
{
    value: s32
}

struct VariadicAnyPair
{
    left:  u64
    right: u64
}

func anyIsS32(value: any)->bool
{
    return @kindof(value) == s32 and cast(s32) value == 42
}

func anyIsBool(value: any)->bool
{
    return @kindof(value) == bool and cast(bool) value
}

func anyIsString(value: any)->bool
{
    return @kindof(value) == string and cast(string) value == "variadic-any"
}

func anyIsBox(value: any)->bool
{
    if @kindof(value) != VariadicAnyBox do
        return false

    let box = cast(VariadicAnyBox) value
    return box.value == 314
}

func anyIsPair(value: any)->bool
{
    if @kindof(value) != VariadicAnyPair do
        return false

    let pair = cast(VariadicAnyPair) value
    return pair.left == 0x1122334455667788'u64 and pair.right == 0x99AABBCCDDEEFF00'u64
}

func anyDataS32(value: any)->s32
{
    let ptr = cast(*s32) @dataof(value)
    return dref ptr
}

func relayAny(value: any)->any
{
    return value
}

func variadicFirstAnyIsS32(values: ...)->bool
{
    return anyIsS32(values[0])
}

func variadicSecondAnyIsString(values: ...)->bool
{
    return anyIsString(values[1])
}

func variadicFirstAnyIsBox(values: ...)->bool
{
    return anyIsBox(values[0])
}

func variadicFirstAnyDataS32(values: ...)->s32
{
    return anyDataS32(values[0])
}

#test
{
    func variadicIndexedAnyToAny(values: ...)->bool
    {
        return anyIsS32(values[0]) and
               anyIsBool(values[1]) and
               anyIsString(values[2]) and
               anyIsBox(values[3]) and
               anyIsPair(values[4])
    }

    const box: VariadicAnyBox = {value: 314}
    const pair: VariadicAnyPair = {left: 0x1122334455667788'u64, right: 0x99AABBCCDDEEFF00'u64}
    const ok = #run variadicIndexedAnyToAny(42's32, true, "variadic-any", box, pair)
    #assert(ok)
}

#test
{
    func variadicIndexedAnyRelay(values: ...)->bool
    {
        let v0 = relayAny(values[0])
        let v1 = relayAny(values[1])
        let v2 = relayAny(values[2])
        return @kindof(v0) == s32 and
               cast(s32) v0 == 42 and
               @kindof(v1) == string and
               cast(string) v1 == "relay" and
               @kindof(v2) == VariadicAnyBox and
               (cast(VariadicAnyBox) v2).value == 314
    }

    const box: VariadicAnyBox = {value: 314}
    const ok = #run variadicIndexedAnyRelay(42's32, "relay", box)
    #assert(ok)
}

#test
{
    func variadicIndexedAnyData(value: any)->s32
    {
        return anyDataS32(value)
    }

    func variadicIndexedAnyDataForward(values: ...)->s32
    {
        return variadicIndexedAnyData(values[0])
    }

    const value = #run variadicIndexedAnyDataForward(1234's32)
    #assert(value == 1234)
}

#test
{
    func variadicDynamicIndexedAnyToAny(values: ...)->bool
    {
        var index: u64 = 0
        if !anyIsS32(values[index]) do
            return false

        index += 1
        if !anyIsString(values[index]) do
            return false

        index += 1
        if !anyIsBox(values[index]) do
            return false

        return true
    }

    const box: VariadicAnyBox = {value: 314}
    const ok = #run variadicDynamicIndexedAnyToAny(42's32, "variadic-any", box)
    #assert(ok)
}

#test
{
    func variadicForeachAnyToAny(values: ...)->bool
    {
        for value, index in values
        {
            if index == 0 and !anyIsS32(value) do
                return false
            if index == 1 and !anyIsString(value) do
                return false
            if index == 2 and !anyIsBox(value) do
                return false
        }

        return @countof(values) == 3
    }

    const box: VariadicAnyBox = {value: 314}
    const ok = #run variadicForeachAnyToAny(42's32, "variadic-any", box)
    #assert(ok)
}

#test
{
    func boxedAnyThroughVariadic()->bool
    {
        var boxed: any = 42's32
        return anyIsS32(boxed) and variadicFirstAnyIsS32(boxed)
    }

    const ok = #run boxedAnyThroughVariadic()
    #assert(ok)
}

#test
{
    func boxedAnyDataThroughVariadic()->s32
    {
        var value: s32 = 1234
        let boxed: any = @mkany(&value, s32)
        return variadicFirstAnyDataS32(boxed)
    }

    const value = #run boxedAnyDataThroughVariadic()
    #assert(value == 1234)
}

#test
{
    func boxedAnyInSecondVariadicSlot()->bool
    {
        var boxed: any = "variadic-any"
        return anyIsString(boxed) and variadicSecondAnyIsString(42's32, boxed)
    }

    const ok = #run boxedAnyInSecondVariadicSlot()
    #assert(ok)
}

#test
{
    func boxedAnyRelayThroughVariadic()->bool
    {
        var boxed: any = 42's32
        let relayed = relayAny(boxed)
        return anyIsS32(relayed) and variadicFirstAnyIsS32(relayed)
    }

    const ok = #run boxedAnyRelayThroughVariadic()
    #assert(ok)
}

#test
{
    func boxedAnyStructThroughVariadic()->bool
    {
        var box: VariadicAnyBox = {value: 314}
        var boxed: any = box
        return anyIsBox(boxed) and variadicFirstAnyIsBox(boxed)
    }

    const ok = #run boxedAnyStructThroughVariadic()
    #assert(ok)
}

#test
{
    func variadicForeachSeesBoxedAny(values: ...)->bool
    {
        for value, index in values
        {
            if index == 0 do
                return anyIsS32(value)
        }

        return false
    }

    func boxedAnyForeachThroughVariadic()->bool
    {
        var boxed: any = 42's32
        return variadicForeachSeesBoxedAny(boxed)
    }

    const ok = #run boxedAnyForeachThroughVariadic()
    #assert(ok)
}

#test
{
    func strictAnyCastThroughVariadic()->bool
    {
        let boxed = cast(VariadicStrictAny) 42's32
        return variadicFirstAnyIsS32(boxed)
    }

    const ok = #run strictAnyCastThroughVariadic()
    #assert(ok)
}

#test
{
    func strictAnyViewThroughVariadic()->bool
    {
        var raw: any = 42's32
        let boxed = dref cast(*VariadicStrictAny) &raw
        return variadicFirstAnyIsS32(boxed)
    }

    const ok = #run strictAnyViewThroughVariadic()
    #assert(ok)
}

#test
{
    func strictAnySecondSlotThroughVariadic()->bool
    {
        let boxed = cast(VariadicStrictAny) "variadic-any"
        return variadicSecondAnyIsString(42's32, boxed)
    }

    const ok = #run strictAnySecondSlotThroughVariadic()
    #assert(ok)
}

#test
{
    func strictAnyDataThroughVariadic()->s32
    {
        var value: s32 = 1234
        var raw: any = @mkany(&value, s32)
        let boxed = dref cast(*VariadicStrictAny) &raw
        return variadicFirstAnyDataS32(boxed)
    }

    const value = #run strictAnyDataThroughVariadic()
    #assert(value == 1234)
}
