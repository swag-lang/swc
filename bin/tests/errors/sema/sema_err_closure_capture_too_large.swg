#global fileprivate

struct Boundary64
{
    a, b, c, d, e, f, g, h: u64
}

struct Capture24
{
    a, b, c: u64
}

alias ClosureUnary = func||(s32)->s32
alias ClosureNullary = func||()->s32
alias ClosureBoundary = func||()->u64

func addOne(value: s32)->s32 => value + 1

#test
{
    let fromLambda: ClosureUnary = func(value: s32)->s32 { return value + 10 }
    let fromFunction: ClosureUnary = &addOne
    var nullable: ClosureNullary = null

    #assert(#typeof(fromLambda) == ClosureUnary)
    #assert(#typeof(fromFunction) == ClosureUnary)
    #assert(#typeof(nullable) == ClosureNullary)
}

#test
{
    let boundary: Boundary64 = {a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8}
    let exact: ClosureBoundary = func|boundary|()->u64 { return boundary.a + boundary.h }
    #assert(#typeof(exact) == ClosureBoundary)
}

#test
{
    var total = 0
    let refCapture: ClosureUnary = func|&total|(value: s32)->s32 { total += value; return total }
    #assert(#typeof(refCapture) == ClosureUnary)
}

#test
{
    let outer = 5
    let bad: ClosureUnary = func(value: s32)->s32 { return outer + value } // swc-expected-error {{sema_err_closure_capture_missing}}
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
