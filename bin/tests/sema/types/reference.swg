#global fileprivate

struct A {}
func titi(a: &A) {}
#test
{
    var a: A
    titi(&a)
    titi(a) // swc-expected-error {{sema_err_cannot_cast}}
}

func tata(a: const &A) {}
#test
{
    var a: A
    tata(a)
}

#test
{
    var a: A
    var b: const &A // swc-expected-error {{sema_err_ref_missing_init}}
}

#test
{
    var a: A
    const b: const &A // swc-expected-error {{sema_err_const_ref_type}}
}

#test
{
    var a: A
    var b: &A = &a
    var c: const &A = &a
    var d: const &A = a
}

struct ConstAddrValue
{
    x: s32
}

struct ConstAddrHolder
{
    value: ConstAddrValue
}

func readConstAddr(value: const &ConstAddrValue)->s32 { return value.x }

#test
{
    let holder: ConstAddrHolder = {value: {x: 123}}
    var valueRef: const &ConstAddrValue = &holder.value
    let result = readConstAddr(&holder.value)

    #assert(#typeof(valueRef) == const &ConstAddrValue)
    #assert(#typeof(result) == s32)
}

func inspectConstScalar(value: const &s32)
{
    let ptr = &value
    #assert(#typeof(ptr) == const *s32)
}

func sumConstAnon(value: const &{ x: s32, y: s32 })->s32
{
    return value.x + value.y
}

struct RefPair
{
    x: s32
    y: s32
}

func sumConstPair(value: const &RefPair)->s32 { return value.x + value.y }

#test
{
    var value: s32 = 41
    inspectConstScalar(value)
    inspectConstScalar(4)
    inspectConstScalar(value + 1)
}

#test
{
    let tupleSum = sumConstAnon({1, 2})
    let pairSum = sumConstPair({x: 3, y: 4})

    #assert(#typeof(tupleSum) == s32)
    #assert(#typeof(pairSum) == s32)
}
