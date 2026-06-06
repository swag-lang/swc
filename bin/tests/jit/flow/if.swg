#global fileprivate

#test
{
    func ifArgNoElse()->s32
    {
        if false
        {
            return 12
        }

        return 11
    }

    const V0 = #run ifArgNoElse()
    #assert(V0 == 11)
}


#test
{
    func ifArgNoElse(flag: bool)->s32
    {
        if flag
        {
            return 11
        }

        return 22
    }

    const V0 = #run ifArgNoElse(true)
    const V1 = #run ifArgNoElse(false)
    #assert(V0 == 11)
    #assert(V1 == 22)
}

#test
{
    func ifElseArg(flag: bool)->s32
    {
        if flag
        {
            return 31
        }
        else
        {
            return 32
        }
    }

    const V0 = #run ifElseArg(true)
    const V1 = #run ifElseArg(false)
    #assert(V0 == 31)
    #assert(V1 == 32)
}

#test
{
    func ifElseIfArgs(flag0: bool, flag1: bool)->s32
    {
        if flag0
        {
            return 51
        }
        elif flag1
        {
            return 52
        }
        else
        {
            return 53
        }
    }

    const V0 = #run ifElseIfArgs(true, false)
    const V1 = #run ifElseIfArgs(false, true)
    const V2 = #run ifElseIfArgs(false, false)
    #assert(V0 == 51)
    #assert(V1 == 52)
    #assert(V2 == 53)
}

#test
{
    func nestedIfArgs(outer: bool, inner: bool)->s32
    {
        if outer
        {
            if inner
            {
                return 71
            }
            else
            {
                return 72
            }
        }

        return 73
    }

    const V0 = #run nestedIfArgs(true, true)
    const V1 = #run nestedIfArgs(true, false)
    const V2 = #run nestedIfArgs(false, true)
    #assert(V0 == 71)
    #assert(V1 == 72)
    #assert(V2 == 73)
}

#test
{
    func earlyReturnAndElif(enabled: bool, text: #null string, hasClear: bool)->s32
    {
        if !enabled do
            return 1

        if text != null and @countof(text)
        {
            if !hasClear do
                return 2
        }
        elif hasClear
        {
            return 3
        }

        return 4
    }

    const V0 = #run earlyReturnAndElif(false, "abc", false)
    const V1 = #run earlyReturnAndElif(true, "abc", false)
    const V2 = #run earlyReturnAndElif(true, "", true)
    const V3 = #run earlyReturnAndElif(true, null, false)
    #assert(V0 == 1)
    #assert(V1 == 2)
    #assert(V2 == 3)
    #assert(V3 == 4)
}

struct EarlyReturnAndElifButton
{
    value: s32
}

impl EarlyReturnAndElifButton
{
    mtd destroy()
    {
        .value = 0
    }
}

struct EarlyReturnAndElifText
{
    length: u64
}

impl EarlyReturnAndElifText
{
    mtd const opCount()->u64
    {
        return .length
    }

    mtd const opEquals(other: string)->bool
    {
        return .length == @countof(other)
    }
}

struct EarlyReturnAndElifBox
{
    enabled: bool
    text:    EarlyReturnAndElifText
    button:  *EarlyReturnAndElifButton
    cb:      func||()
    value:   s32
}

impl EarlyReturnAndElifBox
{
    mtd applyLayout()
    {
        .value += 10
    }

    mtd setText(text: #null string)
    {
        .text.length = @countof(text)
    }

    mtd showHide()
    {
        if !.enabled do
            return

        if .text != null and @countof(.text)
        {
            if !.button
            {
                let box = me
                .button = &EarlyReturnAndElifGlobalButton
                .cb     = func|box|() { box.setText(null); }
                .applyLayout()
            }
        }
        elif .button
        {
            .button.destroy()
            .button = null
            .applyLayout()
        }
    }
}

var EarlyReturnAndElifGlobalButton: EarlyReturnAndElifButton

#test
{
    var box: EarlyReturnAndElifBox
    box.enabled = true
    box.setText("abc")
    box.showHide()
    @assert(box.button != null)
    @assert(box.value == 10)

    box.setText(null)
    box.showHide()
    @assert(box.button == null)
    @assert(box.value == 20)
}
