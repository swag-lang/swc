#global fileprivate // swc-option suite-jit

struct DefaultInner
{
    value: s32 = 9
}

struct DefaultOuter
{
    text:   string   = "jit"
    inner:  DefaultInner
    digits: [3] u8   = [1, 2, 3]
    tail:   s32      = 11
}

#test
{
    func localStructDefaults()->bool
    {
        var value: DefaultOuter
        return value.text == "jit" and value.inner.value == 9 and value.digits[0] == 1 and value.digits[2] == 3 and value.tail == 11
    }

    const V = #run localStructDefaults()
    #assert(V)
}

#test
{
    func anyStructDefaults()->bool
    {
        var value: DefaultOuter
        var boxed: any = value
        let refValue = cast(const &DefaultOuter) boxed
        var copyValue = cast(DefaultOuter) boxed
        copyValue.tail = 42
        return refValue.text == "jit" and refValue.inner.value == 9 and refValue.digits[1] == 2 and refValue.tail == 11 and copyValue.tail == 42
    }

    const V = #run anyStructDefaults()
    #assert(V)
}
