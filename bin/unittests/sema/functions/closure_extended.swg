#global private
#global #[Swag.ExplicitNullability]

struct Pair
{
    base: s32
    step: s32
}

struct Holder
{
    cb: func||(s32)->s32
}

struct Capture24
{
    a, b, c: u64
}

struct PathTarget
{
    value: s32
}

struct PathHolder
{
    target: #null *PathTarget
}

struct PathOwner
{
    target: #null *PathTarget
    bias:   s32
}

alias ClosureUnary = func||(s32)->s32
alias ClosureNullary = func||()->s32

var GlobalSeed = 41

func addOne(value: s32)->s32 => value + 1
func acceptUnary(cb: ClosureUnary)->ClosureUnary => cb
func acceptNullary(cb: ClosureNullary = null)->ClosureNullary => cb

impl PathOwner
{
    mtd makeCallback()->ClosureNullary
    {
        return func|me.target, me.bias|()->s32 { return (target orelse null).value + bias }
    }
}

func semaTest001()
{
    var cb: ClosureUnary = null
    cb = func(value: s32)->s32 { return value + 1 }
    cb = &addOne
    let offset = 7
    cb = func|offset|(value: s32)->s32 { return offset + value }

    #assert(#typeof(cb) == ClosureUnary)
}

func semaTest002()
{
    var holders: [2] Holder
    holders[0].cb = func(value: s32)->s32 { return value }

    let pair: Pair = {base: 4, step: 6}
    holders[1].cb = func|pair|(value: s32)->s32 { return pair.base + pair.step + value }

    #assert(#typeof(holders[0].cb) == ClosureUnary)
    #assert(#typeof(acceptUnary(holders[1].cb)) == ClosureUnary)
}

func semaTest003()
{
    let globalReader: ClosureNullary = func()->s32 { return GlobalSeed }
    let fromLambda = acceptUnary(func(value: s32)->s32 { return value * 2 })
    let fromNull = acceptNullary()

    #assert(#typeof(globalReader) == ClosureNullary)
    #assert(#typeof(fromLambda) == ClosureUnary)
    #assert(#typeof(fromNull) == ClosureNullary)
}

func semaTest004()
{
    var target: PathTarget
    var holder: PathHolder
    holder.target = &target

    let cb: ClosureNullary = func|holder.target|()->s32 { return target.value }
    #assert(#typeof(cb) == ClosureNullary)
}

func semaTest005()
{
    var target: PathTarget
    var owner: PathOwner
    owner.target = &target
    owner.bias   = 3

    let cb = owner.makeCallback()
    #assert(#typeof(cb) == ClosureNullary)
}
