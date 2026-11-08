#global private
enum CmpEnum: u16
{
    A = 10
    B = 20
}

#[Swag.Strict]
alias CompareStrictEnum        = CmpEnum

#[Swag.Strict]
alias CompareStrictAny         = any

#[Swag.Strict]
alias CompareStrictS32Ptr      = [*] s32

#[Swag.Strict]
alias CompareOtherStrictS32Ptr = [*] s32

#[Swag.Strict]
alias CompareStrictS32         = s32

#[Swag.Strict]
alias CompareStrictF32         = f32

struct CompareIdentityBase
{
    value: s32
}

struct CompareIdentityDerived
{
    using base: CompareIdentityBase
    extra:      s32
}

var CompareCounter: s32

func touch(flag: bool, delta: s32)->bool
{
    CompareCounter += delta
    return flag
}

// Pointer equality and null comparison
#test
{
    var a: *s32? = null
    let b        = a == null
    let c        = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
    Swag.require(b)
    Swag.require(not c)
}

// Relational operators on integers
#test
{
    let a = -5 < 12
    let b = 12 <= 12
    let c = 0xFFFF_FFFF_FFFF_FFFF'u64 > 1'u64
    let d = 9'u64 >= 9'u64

    Swag.require(a)
    Swag.require(b)
    Swag.require(c)
    Swag.require(d)
}

// Three-way comparison operator on integers
#test
{
    let a = 1 <=> 2
    let b = 2 <=> 1
    let c = 7 <=> 7

    #assert(#typeof(a) == s32)

    Swag.require(a == -1)
    Swag.require(b == 1)
    Swag.require(c == 0)
}

// Float comparison and three-way compare
#test
{
    let a = 1.5'f64 < 2.5'f64
    let b = 2.5'f64 <=> 1.5'f64
    let c = 3.25'f64 <=> 3.25'f64

    Swag.require(a)
    Swag.require(b == 1)
    Swag.require(c == 0)
}

// Enum equality comparison
#test
{
    let a = CmpEnum.A == CmpEnum.A
    let b = CmpEnum.A != CmpEnum.B

    Swag.require(a)
    Swag.require(b)
}

// Ordered enum operands retain their enum type when another comparison uses them.
#test
{
    var value = CmpEnum.B
    Swag.require(value >= .A)
    Swag.require(value <= .B)
    Swag.require(value > .A)
    Swag.require(not (value < .B))
}

#test
{
    let a = cast(CompareStrictEnum, CmpEnum.A)
    let b = cast(CompareStrictEnum, CmpEnum.B)

    Swag.require(a == cast(CompareStrictEnum, CmpEnum.A))
    Swag.require(a != b)
    Swag.require(a < b)
    Swag.require(b > a)
    Swag.require((a <=> b) == -1)
}

// Pointer identity comparison
#test
{
    var value0: s32 = 77
    var value1: s32 = 10
    let p0          = &value0
    let p1          = p0
    let p2          = &value1

    Swag.require(p0 == p1)
    Swag.require(p0 != p2)
    Swag.require(p2 != null)
}

// Struct references compare by identity when paired with pointers
#test
{
    var base    = CompareIdentityBase{value: 10}
    var other   = CompareIdentityBase{value: 20}
    var derived = CompareIdentityDerived{base: CompareIdentityBase{value: 30}, extra: 40}

    let basePtr:        *CompareIdentityBase = &base
    let otherPtr:       *CompareIdentityBase = &other
    let derivedBasePtr: *CompareIdentityBase = &derived.base

    var baseRef:    *CompareIdentityBase       = &base
    let otherRef:   const *CompareIdentityBase = &other
    var derivedRef: *CompareIdentityDerived    = &derived

    Swag.require(basePtr == baseRef)
    Swag.require(baseRef == basePtr)
    Swag.require(basePtr != otherRef)
    Swag.require(otherRef != basePtr)
    Swag.require(otherPtr != baseRef)
    Swag.require(derivedBasePtr == derivedRef)
    Swag.require(derivedRef == derivedBasePtr)
    Swag.require(derivedBasePtr != baseRef)
}

func matchReferenceValue(value: s32)->bool
{
    return value == 4 and value != 5 and value < 5 and value <= 4 and value > 3 and value >= 4 and
           (value <=> 4) == 0 and (value <=> 5) == -1 and (value <=> 3) == 1
}

// Scalar references compare like their pointee values
#test
{
    var x: s32 = 42
    var y: s32 = 42
    var z: s32 = 7

    var refX: *s32       = &x
    let refY: const *s32 = &y
    let refZ: const *s32 = &z

    Swag.require(refX[] == 42)
    Swag.require(42 == refX[])
    Swag.require(refX[] != 7)
    Swag.require(7 != refX[])
    Swag.require(refX[] < 50)
    Swag.require(41 < refX[])
    Swag.require(refX[] <= 42)
    Swag.require(42 <= refX[])
    Swag.require(refX[] > 10)
    Swag.require(50 > refX[])
    Swag.require(refX[] >= 42)
    Swag.require(42 >= refX[])
    Swag.require((refX[] <=> 42) == 0)
    Swag.require((refX[] <=> 50) == -1)
    Swag.require((50 <=> refX[]) == 1)
    Swag.require(refX[] == refY[])
    Swag.require(refX[] != refZ[])
}

// Const-reference parameters keep value-style comparisons
#test
{
    var value:    s32        = 4
    let valueRef: const *s32 = &value
    Swag.require(matchReferenceValue(valueRef[]))
}

// Float references use the same comparison pipeline
#test
{
    var value:    f32        = 1.5
    let valueRef: const *f32 = &value

    Swag.require(valueRef[] == 1.5)
    Swag.require(valueRef[] != 2.5)
    Swag.require(valueRef[] < 2.5)
    Swag.require(valueRef[] <= 1.5)
    Swag.require(valueRef[] > 1.0)
    Swag.require(valueRef[] >= 1.5)
    Swag.require((valueRef[] <=> 1.5) == 0)
}

// Short-circuit evaluation with side effects
#test
{
    CompareCounter = 0
    let a = touch(false, 1) and touch(true, 10)
    let b = touch(true, 100) or touch(true, 1000)

    Swag.require(not a)
    Swag.require(b)
    Swag.require(CompareCounter == 101)
}

#test
{
    var value: s32 = 42
    var raw:   any = Swag.makeAny(&value, s32)
    let boxed      = cast(const *CompareStrictAny, (&raw))[]

    Swag.require(boxed is s32)
    Swag.require(boxed is s32)
    Swag.require(not (boxed is string))
    Swag.require(not (boxed is string))
}

#test
{
    var data: [3] s32 = [10, 20, 30]
    let raw0          = cast([*] s32, &data[0])
    let raw1          = cast([*] s32, &data[1])
    let strict0       = cast(CompareStrictS32Ptr, raw0)
    let strict1       = cast(CompareStrictS32Ptr, raw1)
    let other0        = cast(CompareOtherStrictS32Ptr, raw0)

    Swag.require(strict0 == raw0)
    Swag.require(raw0 == strict0)
    Swag.require(strict0 == other0)
    Swag.require(strict0 != strict1)
    Swag.require(strict0 < strict1)
    Swag.require(strict1 > strict0)
    Swag.require(strict0 <= strict0)
    Swag.require(strict1 >= strict0)
    Swag.require((strict0 <=> strict1) == -1)
    Swag.require((strict1 <=> strict0) == 1)
    Swag.require((strict0 <=> other0) == 0)
}

func compareStrictIntLess(a, b: CompareStrictS32)->bool
{
    return a < b
}

func compareStrictFloatSpaceship(a, b: CompareStrictF32)->s32
{
    return a <=> b
}

#test
{
    let i0 = cast(CompareStrictS32, 10)
    let i1 = cast(CompareStrictS32, 20)
    let f0 = cast(CompareStrictF32, 1.5)
    let f1 = cast(CompareStrictF32, 2.5)

    Swag.require(i0 == cast(CompareStrictS32, 10))
    Swag.require(i0 != i1)
    Swag.require(i0 < i1)
    Swag.require(i0 <= i0)
    Swag.require(i1 > i0)
    Swag.require(i1 >= i0)
    Swag.require((i0 <=> i1) == -1)
    Swag.require((i1 <=> i0) == 1)
    Swag.require((i0 <=> i0) == 0)
    Swag.require(compareStrictIntLess(i0, i1))

    Swag.require(f0 < f1)
    Swag.require(f0 <= f0)
    Swag.require(f1 > f0)
    Swag.require(f1 >= f0)
    Swag.require((f0 <=> f1) == -1)
    Swag.require(compareStrictFloatSpaceship(f1, f0) == 1)
}

#test
{
    const i0 = cast(CompareStrictS32, 10)
    const i1 = cast(CompareStrictS32, 20)
    const f0 = cast(CompareStrictF32, 1.5)
    const f1 = cast(CompareStrictF32, 2.5)

    #assert(i0 < i1)
    #assert(i0 <= i0)
    #assert(i1 > i0)
    #assert(i1 >= i0)
    #assert((i0 <=> i1) == -1)
    #assert(f0 < f1)
    #assert((f1 <=> f0) == 1)
}

interface ICompareAllocator
{
    mtd reserve()->u32
}

struct CompareAllocator
{
    id: u32
}

impl ICompareAllocator for CompareAllocator
{
    mtd impl reserve()->u32 => .id
}

struct CompareAllocatorHolder
{
    allocator: ICompareAllocator?
}

impl CompareAllocatorHolder
{
    mtd needsAllocator()->bool
    {
        return .allocator == null
    }

    mtd needsAllocatorLeft()->bool
    {
        return null == .allocator
    }

    mtd hasAllocator()->bool
    {
        return .allocator != null
    }
}

#test
{
    var holder = CompareAllocatorHolder{}
    Swag.require(holder.needsAllocator())
    Swag.require(holder.needsAllocatorLeft())
    Swag.require(not holder.hasAllocator())

    var alloc = CompareAllocator{id: 55}
    holder.allocator = alloc
    Swag.require(not holder.needsAllocator())
    Swag.require(not holder.needsAllocatorLeft())
    Swag.require(holder.hasAllocator())
    Swag.require(holder.allocator.reserve() == 55)
}
