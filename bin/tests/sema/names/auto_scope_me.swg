#global fileprivate

struct A
{
    count: s32
    x: s32
    y: s32
}

impl A
{
    mtd const whereFunction(n: s32)->bool => .count == n

    mtd foo()
    {
        let a = .x
        #assert(#typeof(a) == s32)
        let b = .x + .y
    }
}

#test
{
    let value = A{count: 3, x: 1, y: 2}
    let ok = value.whereFunction(3)
    #assert(#typeof(ok) == bool)
}

interface I
{
}

impl I for A
{
    mtd bar()
    {
        let a = .x
        #assert(#typeof(a) == s32)
        let b = .x + .y
    }
}

struct(T) AutoScopeUnaryBox
{
    value: T
}

impl AutoScopeUnaryBox
{
    func(op: string) opUnary(const me)->AutoScopeUnaryBox'T
    {
        #if op == "~" do
            return {value: ~.value}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

#test
{
    var value: AutoScopeUnaryBox's32 = {value: 42}
    let inverted = ~value
    #assert(#typeof(inverted) == AutoScopeUnaryBox's32)
    #assert(#typeof(inverted.value) == s32)
}
