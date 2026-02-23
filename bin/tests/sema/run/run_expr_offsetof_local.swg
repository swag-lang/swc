#global internal

struct OffPair
{
    a: u8
    b: u64
}

#test
{
    func scalarLayout()->u64
    {
        let a: s8 = 1
        let b: s16 = 2
        let c: s32 = 3
        let d: s64 = 4

        #assert(#offsetof(a) == 0)
        #assert(#offsetof(b) == 2)
        #assert(#offsetof(c) == 4)
        #assert(#offsetof(d) == 8)

        return cast(u64) #offsetof(a) + cast(u64) #offsetof(b) + cast(u64) #offsetof(c) + cast(u64) #offsetof(d)
    }

    const V = #run scalarLayout()
    #assert(V == 14'u64)
}

#test
{
    func stringAndNested()->u64
    {
        let head: s8 = 0
        {
            let inner: string = "x"
            #assert(#offsetof(inner) == 8)
        }

        let tail: u16 = 7
        #assert(#offsetof(tail) == 16)

        return cast(u64) #offsetof(head) + cast(u64) #offsetof(tail)
    }

    const V = #run stringAndNested()
    #assert(V == 16'u64)
}

#test
{
    func multiDecl()->u64
    {
        var a, b: s32 = 1
        #assert(#offsetof(a) == 0)
        #assert(#offsetof(b) == 4)
        return cast(u64) #offsetof(b)
    }

    const V = #run multiDecl()
    #assert(V == 4'u64)
}

#test
{
    func aggregateLayout()->u64
    {
        let lead: s8 = 0
        let pair: OffPair = {a: 1, b: 2}
        let tail: s16 = 0

        #assert(#offsetof(lead) == 0)
        #assert(#offsetof(pair) == 8)
        #assert(#offsetof(tail) == 24)

        return cast(u64) #offsetof(tail)
    }

    const V = #run aggregateLayout()
    #assert(V == 24'u64)
}

#test
{
    const V = #offsetof(5) // swc-expected-error {{sema_err_invalid_offsetof}}
}

#test
{
    func bad()->u64
    {
        let a: s32 = 0
        return cast(u64) a
    }

    const V = #offsetof(bad()) // swc-expected-error {{sema_err_invalid_offsetof}}
}
