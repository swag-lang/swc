#global private

struct Counter
{
    count: s32
}

#[Swag.EnumFlags]
enum AutoScopeAttributes
{
    Zero = 0
    Directory
}

struct AutoScopeFileInfo
{
    attributes = AutoScopeAttributes.Zero
}

func(T) has(flags, value: T)->bool
{
    return (flags & value) != cast(T) 0
}

impl Counter
{
    mtd const whereFunction(n: s32)->bool => .count == n
}

impl AutoScopeFileInfo
{
    mtd const isDirectory()->bool => .attributes.has(.Directory)
}

#test
{
    let counter = Counter{count: 4}
    @assert(counter.whereFunction(4))
    @assert(!counter.whereFunction(3))

    let info = AutoScopeFileInfo{attributes: AutoScopeAttributes.Directory}
    @assert(info.isDirectory())
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
