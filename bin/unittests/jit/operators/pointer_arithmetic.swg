#global private

struct PointerFieldHolder
{
    ptr: [*] u8
    len: s32
    buf: [8] u8
}

impl PointerFieldHolder
{
    mtd assignArrayFieldToPointer()
    {
        .ptr = .buf
    }

    mtd writeAfterPointerOffset()->u16
    {
        .len = 4
        .assignArrayFieldToPointer()
        var tail = cast([*] u16) (.ptr + .len)
        dref tail = 0x1234'u16
        return cast(u16) .buf[4] | (cast(u16) .buf[5] << 8)
    }
}

#test
{
    func pointerStepAndDistance()->s64
    {
        var arr: [6] u16 = [10, 20, 30, 40, 50, 60]
        let base = cast([*] u16) &arr[0]
        let next = 1 + base
        var ptr  = base
        ptr += 4
        ptr -= 2
        return (ptr - next) * 100 + dref ptr + dref next
    }

    const V = #run pointerStepAndDistance()
    #assert(V == 150)
}

#test
{
    func reversePointerWalk()->s32
    {
        var arr: [4] s32 = [1, 3, 5, 7]
        var ptr          = cast([*] s32) &arr[3]
        var acc: s32     = 0
        for 4
        {
            acc += dref ptr
            ptr -= 1
        }

        return acc
    }

    const V = #run reversePointerWalk()
    #assert(V == 16)
}

#test
{
    func pointerIndexAfterTypedStep()->u8
    {
        var arr: [4] u8 = [0, 1, 2, 3]
        var ptr         = cast([*] u8) &arr[0]
        ptr += 1'u8
        let c = ptr[0]
        return ptr[c]
    }

    const V = #run pointerIndexAfterTypedStep()
    #assert(V == 2'u8)
}

#test
{
    func pointerDifferenceFromOffset()->s64
    {
        var arr: [8] u8
        let base = cast([*] u8) &arr[0]
        let tail = cast([*] u8) &arr[6]
        return tail - (2 + base)
    }

    const V = #run pointerDifferenceFromOffset()
    #assert(V == 4)
}

#test
{
    func arrayFieldPointerDecay()->u16
    {
        var holder: PointerFieldHolder
        return holder.writeAfterPointerOffset()
    }

    const V = #run arrayFieldPointerDecay()
    #assert(V == 0x1234'u16)
}
