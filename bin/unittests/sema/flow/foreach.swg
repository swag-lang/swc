#global private

#[Swag.Strict]
alias ForeachStrictArray = [3] s32

#[Swag.Strict]
alias ForeachStrictSlice = [..] s32

struct ForeachAliasBuffer
{
    data: [3] u8
}

impl ForeachAliasBuffer
{
    #[Macro, Swag.CalleeReturn]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if back do
            #error("reverse visit not supported")

        for @countof(.data)
        {
            #macro
            {
                #if #up ptr do
                    var #alias0 = &me.data[@index]
                #else do
                    var #alias0 = me.data[@index]
                var #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

func semaTest001()
{
    var arr: [3] s32 = [1, 2, 3]
    foreach v in arr
    {
        #assert(#typeof(v) == s32)
        var x = v
    }
}

func semaTest002()
{
    var arr: ForeachStrictArray = cast(ForeachStrictArray) [4, 5, 6]
    foreach v, i in arr
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}

func semaTest003()
{
    var arr: [2] s32 = [1, 2]
    foreach v in arr where v > 0
    {
        var x = v
    }
}

func semaTest004()
{
    var arr: [2] u32 = [10'u32, 20]
    foreach &v in arr
    {
        var x = dref v
    }
}

func semaTest005()
{
    var text: string = "AB"
    foreach v, i in text
    {
        #assert(#typeof(v) == u8)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}

func semaTest006()
{
    var arr: [2] s32 = [3, 4]
    var sl = cast([..] s32) arr
    foreach v, i in sl
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}

func semaTest007()
{
    var arr: [2] s32 = [5, 6]
    var rawSl = cast([..] s32) arr
    var sl: ForeachStrictSlice = cast(ForeachStrictSlice) rawSl
    foreach v, i in sl
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }
}

func semaTest008()
{
    func foreachVariadicAny(values: ...)
    {
        foreach v, i in values
        {
            #assert(#typeof(v) == any)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
        }
    }
}

func semaTest009()
{
    func foreachVariadicTyped(values: s32...)
    {
        foreach v, i in values
        {
            #assert(#typeof(v) == s32)
            #assert(#typeof(i) == u64)
            var x = v
            var y = i
        }
    }
}

func semaTest010()
{
    enum Priority: u32
    {
        Low    = 1
        Normal = 5
        High   = 10
    }

    foreach value, idx in Priority
    {
        #assert(#typeof(value) == Priority)
        #assert(#typeof(idx) == u64)
        var x = value
        var y = idx
    }
}

func semaTest011()
{
    let text: ForeachAliasBuffer = {data: ['a''u8, 'b''u8, 'c''u8]}
    var freq: [3, 26] u32

    foreach c, i in text
    {
        var cell: &u32 = &freq[i, c - 'a']
        cell += 1'u32
    }
}
