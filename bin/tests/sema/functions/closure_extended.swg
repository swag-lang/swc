#global fileprivate

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
    target: *PathTarget
}

struct PathOwner
{
    target: *PathTarget
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
        return func|me.target, me.bias|()->s32 { return target.value + bias }
    }
}

#test
{
    var cb: ClosureUnary = null
    cb = func(value: s32)->s32 { return value + 1 }
    cb = &addOne
    let offset = 7
    cb = func|offset|(value: s32)->s32 { return offset + value }

    #assert(#typeof(cb) == ClosureUnary)
}

#test
{
    var holders: [2] Holder
    holders[0].cb = func(value: s32)->s32 { return value }

    let pair: Pair = {base: 4, step: 6}
    holders[1].cb = func|pair|(value: s32)->s32 { return pair.base + pair.step + value }

    #assert(#typeof(holders[0].cb) == ClosureUnary)
    #assert(#typeof(acceptUnary(holders[1].cb)) == ClosureUnary)
}

#test
{
    let globalReader: ClosureNullary = func()->s32 { return GlobalSeed }
    let fromLambda = acceptUnary(func(value: s32)->s32 { return value * 2 })
    let fromNull = acceptNullary()

    #assert(#typeof(globalReader) == ClosureNullary)
    #assert(#typeof(fromLambda) == ClosureUnary)
    #assert(#typeof(fromNull) == ClosureNullary)
}

#test
{
    var target: PathTarget
    var holder: PathHolder
    holder.target = &target

    let cb: ClosureNullary = func|holder.target|()->s32 { return target.value }
    #assert(#typeof(cb) == ClosureNullary)
}

#test
{
    var target: PathTarget
    var owner: PathOwner
    owner.target = &target
    owner.bias   = 3

    let cb = owner.makeCallback()
    #assert(#typeof(cb) == ClosureNullary)
}

#test
{
    let outer = 5
    let bad: ClosureUnary = func(value: s32)->s32 { return outer + value } // swc-expected-error {{sema_err_closure_capture_missing}}
}

#test
{
    let outer = 7
    let bad: ClosureNullary = func|outer|()->s32
    {
        let inner = func()->s32 { return outer } // swc-expected-error {{sema_err_closure_capture_missing}}
        return inner()
    }
}

#test
{
    let fixed = 10
    let bad: ClosureNullary = func|&fixed|()->s32 { return fixed } // swc-expected-error {{sema_err_take_address_constant}}
}

#test
{
    let bad: ClosureNullary = func|addOne|()->s32 { return 0 } // swc-expected-error {{sema_err_closure_capture_invalid}}
}

#test
{
    var value = 1
    let bad: ClosureNullary = func|value, value|()->s32 { return value } // swc-expected-error {{sema_err_closure_capture_invalid}}
}

#test
{
    let base = 7
    let bad: func(s32)->s32 = func|base|(value: s32)->s32 { return base + value }
} // swc-expected-error {{sema_err_cannot_cast}}

#test
{
    let a: Capture24 = {a: 1, b: 2, c: 3}
    let b: Capture24 = {a: 4, b: 5, c: 6}
    let c: Capture24 = {a: 7, b: 8, c: 9}
    let tooBig = func|a, b, c|() {} // swc-expected-error {{sema_err_closure_capture_too_large}}
}
