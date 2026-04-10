#global fileprivate
enum CmpEnum: u16
{
    A = 10
    B = 20
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
    var a: *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
    @assert(b)
    @assert(!c)
}

// Relational operators on integers
#test
{
    let a = -5 < 12
    let b = 12 <= 12
    let c = 0xFFFF_FFFF_FFFF_FFFF'u64 > 1'u64
    let d = 9'u64 >= 9'u64

    @assert(a)
    @assert(b)
    @assert(c)
    @assert(d)
}

// Three-way comparison operator on integers
#test
{
    let a = 1 <=> 2
    let b = 2 <=> 1
    let c = 7 <=> 7

    #assert(#typeof(a) == s32)

    @assert(a == -1)
    @assert(b == 1)
    @assert(c == 0)
}

// Float comparison and three-way compare
#test
{
    let a = 1.5'f64 < 2.5'f64
    let b = 2.5'f64 <=> 1.5'f64
    let c = 3.25'f64 <=> 3.25'f64

    @assert(a)
    @assert(b == 1)
    @assert(c == 0)
}

// Enum equality comparison
#test
{
    let a = CmpEnum.A == CmpEnum.A
    let b = CmpEnum.A != CmpEnum.B

    @assert(a)
    @assert(b)
}

// Pointer identity comparison
#test
{
    var value0: s32 = 77
    var value1: s32 = 10
    let p0 = &value0
    let p1 = p0
    let p2 = &value1

    @assert(p0 == p1)
    @assert(p0 != p2)
    @assert(p2 != null)
}

func matchReferenceValue(value: const &s32)->bool
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

    var refX: &s32 = &x
    let refY: const &s32 = &y
    let refZ: const &s32 = &z

    @assert(refX == 42)
    @assert(42 == refX)
    @assert(refX != 7)
    @assert(7 != refX)
    @assert(refX < 50)
    @assert(41 < refX)
    @assert(refX <= 42)
    @assert(42 <= refX)
    @assert(refX > 10)
    @assert(50 > refX)
    @assert(refX >= 42)
    @assert(42 >= refX)
    @assert((refX <=> 42) == 0)
    @assert((refX <=> 50) == -1)
    @assert((50 <=> refX) == 1)
    @assert(refX == refY)
    @assert(refX != refZ)
}

// Const-reference parameters keep value-style comparisons
#test
{
    var value: s32 = 4
    let valueRef: const &s32 = &value
    @assert(matchReferenceValue(valueRef))
}

// Float references use the same comparison pipeline
#test
{
    var value: f32 = 1.5
    let valueRef: const &f32 = &value

    @assert(valueRef == 1.5)
    @assert(valueRef != 2.5)
    @assert(valueRef < 2.5)
    @assert(valueRef <= 1.5)
    @assert(valueRef > 1.0)
    @assert(valueRef >= 1.5)
    @assert((valueRef <=> 1.5) == 0)
}

// Short-circuit evaluation with side effects
#test
{
    CompareCounter = 0
    let a = touch(false, 1) and touch(true, 10)
    let b = touch(true, 100) or touch(true, 1000)

    @assert(!a)
    @assert(b)
    @assert(CompareCounter == 101)
}
