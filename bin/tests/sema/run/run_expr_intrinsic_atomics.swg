#global fileprivate

#test
{
    #[Swag.NoInline]
    func atomAddS32(ptr: *s32, value: s32)->s32 => @atomadd(ptr, value)
    #[Swag.NoInline]
    func atomAndU32(ptr: *u32, value: u32)->u32 => @atomand(ptr, value)
    #[Swag.NoInline]
    func atomOrU32(ptr: *u32, value: u32)->u32 => @atomor(ptr, value)
    #[Swag.NoInline]
    func atomXorU32(ptr: *u32, value: u32)->u32 => @atomxor(ptr, value)
    #[Swag.NoInline]
    func atomXchgU32(ptr: *u32, value: u32)->u32 => @atomxchg(ptr, value)
    #[Swag.NoInline]
    func atomCmpXchgS32(ptr: *s32, compareTo, exchangeWith: s32)->s32 => @atomcmpxchg(ptr, compareTo, exchangeWith)

    #[Swag.NoInline]
    func runAtomAdd()->bool
    {
        var x = 0's32
        let a = atomAddS32(&x, 1)
        let b = atomAddS32(&x, 2)
        return a == 0 and b == 1 and x == 3
    }

    #[Swag.NoInline]
    func runAtomAnd()->bool
    {
        var x = 0xFF'u32
        let a = atomAndU32(&x, 3)
        let b = atomAndU32(&x, 2)
        return a == 0xFF and b == 3 and x == 2
    }

    #[Swag.NoInline]
    func runAtomOr()->bool
    {
        var x = 0'u32
        let a = atomOrU32(&x, 1)
        let b = atomOrU32(&x, 2)
        return a == 0 and b == 1 and x == 3
    }

    #[Swag.NoInline]
    func runAtomXor()->bool
    {
        var x = 7'u32
        let a = atomXorU32(&x, 3)
        let b = atomXorU32(&x, 4)
        return a == 7 and b == 4 and x == 0
    }

    #[Swag.NoInline]
    func runAtomXchg()->bool
    {
        var x = 10'u32
        let a = atomXchgU32(&x, 20)
        return a == 10 and x == 20
    }

    #[Swag.NoInline]
    func runAtomCmpXchg()->bool
    {
        var x = 7's32
        let a = atomCmpXchgS32(&x, 7, 3)
        let b = atomCmpXchgS32(&x, 3, 5)
        let c = atomCmpXchgS32(&x, 66, 66)
        return a == 7 and b == 3 and c == 5 and x == 5
    }

    const A = #run runAtomAdd()
    const B = #run runAtomAnd()
    const C = #run runAtomOr()
    const D = #run runAtomXor()
    const E = #run runAtomXchg()
    const F = #run runAtomCmpXchg()

    #assert(A)
    #assert(B)
    #assert(C)
    #assert(D)
    #assert(E)
    #assert(F)
}
