#global private

struct LateItem
{
    value: s32
}

struct LateBox
{
    item: #late *LateItem
}

// =============================================
// Reading a '#late' field before initialization panics under null safety
// =============================================

#test
{
    #[Swag.Safety(.Null, true)]
    func lateReadBeforeInit()->s32
    {
        var b: LateBox
        let p = b.item // swc-expected-error {{safety_err_runtime}}
        return p.value
    }

    const value = #run lateReadBeforeInit()
}

// =============================================
// After the first assignment, reads are free
// =============================================

#test
{
    #[Swag.Safety(.Null, true)]
    func lateReadAfterInit()->s32
    {
        var item = LateItem{value: 42}
        var b: LateBox
        b.item = &item
        return b.item.value
    }

    const value = #run lateReadAfterInit()
    #assert(value == 42)
}

// =============================================
// '#isset' and pure stores never trip the guard
// =============================================

#test
{
    #[Swag.Safety(.Null, true)]
    func lateIsSetNoPanic()->bool
    {
        var item = LateItem{value: 1}
        var b: LateBox
        if #isset(b.item) do
            return false
        b.item = &item
        return #isset(b.item)
    }

    const value = #run lateIsSetNoPanic()
    #assert(value == true)
}

// =============================================
// With null safety disabled, the read is unguarded (C-like)
// =============================================

#test
{
    #[Swag.Safety(.Null, false)]
    func lateNoSafety()->bool
    {
        var b: LateBox
        return #isset(b.item) == false
    }

    const value = #run lateNoSafety()
    #assert(value == true)
}
