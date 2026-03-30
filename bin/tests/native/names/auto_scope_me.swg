#global fileprivate

struct Counter
{
    count: s32
}

impl Counter
{
    mtd const whereFunction(n: s32)->bool => .count == n
}

#test
{
    let counter = Counter{count: 4}
    @assert(counter.whereFunction(4))
    @assert(!counter.whereFunction(3))
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
    @assert(inverted.value == -43)
}
