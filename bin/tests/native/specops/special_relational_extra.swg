#global fileprivate

// ============================================================================
// Standalone opEquals (no opCompare defined)
// ============================================================================

struct RuntimeEqualOnlyBox
{
    a: s32
    b: s32
}

impl RuntimeEqualOnlyBox
{
    #[Swag.NoInline]
    mtd const opEquals(other: const &RuntimeEqualOnlyBox)->bool
    {
        return .a == other.a and .b == other.b
    }
}

// Test: equal values
#test
{
    var lhs = RuntimeEqualOnlyBox{a: 1, b: 2}
    var rhs = RuntimeEqualOnlyBox{a: 1, b: 2}

    @assert(lhs == rhs)
    @assert(!(lhs != rhs))
}

// Test: different first field
#test
{
    var lhs = RuntimeEqualOnlyBox{a: 1, b: 2}
    var rhs = RuntimeEqualOnlyBox{a: 9, b: 2}

    @assert(lhs != rhs)
    @assert(!(lhs == rhs))
}

// Test: different second field
#test
{
    var lhs = RuntimeEqualOnlyBox{a: 1, b: 2}
    var rhs = RuntimeEqualOnlyBox{a: 1, b: 9}

    @assert(lhs != rhs)
}

// Test: reflexivity (x == x)
#test
{
    var x = RuntimeEqualOnlyBox{a: 42, b: 77}

    @assert(x == x)
    @assert(!(x != x))
}

// ============================================================================
// opEquals with f32 operand
// ============================================================================

struct RuntimeFloatCmpBox
{
    value: f32
}

impl RuntimeFloatCmpBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: f32)->bool
    {
        return .value == other
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCompare(other: f32)->s32
    {
        if .value < other do return -1
        if .value > other do return 1
        return 0
    }
}

// Test: opEquals with f32
#test
{
    var box = RuntimeFloatCmpBox{value: 3.14}

    @assert(box == 3.14'f32)
    @assert(box != 2.71'f32)
}

// Test: opCompare with f32 - less than
#test
{
    var box = RuntimeFloatCmpBox{value: 1.0}

    @assert(box < 2.0'f32)
    @assert(box <= 1.0'f32)
    @assert(box <= 2.0'f32)
}

// Test: opCompare with f32 - greater than
#test
{
    var box = RuntimeFloatCmpBox{value: 5.0}

    @assert(box > 3.0'f32)
    @assert(box >= 5.0'f32)
    @assert(box >= 3.0'f32)
}

// Test: opCompare spaceship with f32
#test
{
    var box = RuntimeFloatCmpBox{value: 2.0}

    @assert((box <=> 2.0'f32) == 0)
    @assert((box <=> 3.0'f32) == -1)
    @assert((box <=> 1.0'f32) == 1)
}

// ============================================================================
// opEquals with three overloaded types
// ============================================================================

struct RuntimeTripleEqBox
{
    value: s32
}

impl RuntimeTripleEqBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: const &RuntimeTripleEqBox)->bool
    {
        return .value == other.value
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: s32)->bool
    {
        return .value == other
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: u64)->bool
    {
        return cast(u64) .value == other
    }
}

// Test: struct-struct equality
#test
{
    var a = RuntimeTripleEqBox{value: 10}
    var b = RuntimeTripleEqBox{value: 10}
    var c = RuntimeTripleEqBox{value: 20}

    @assert(a == b)
    @assert(a != c)
}

// Test: struct-s32 equality
#test
{
    var box = RuntimeTripleEqBox{value: 42}

    @assert(box == 42's32)
    @assert(box != 0's32)
}

// Test: struct-u64 equality
#test
{
    var box = RuntimeTripleEqBox{value: 100}

    @assert(box == 100'u64)
    @assert(box != 200'u64)
}

// ============================================================================
// opCompare with three overloaded types
// ============================================================================

struct RuntimeTripleCmpBox
{
    value: s32
}

impl RuntimeTripleCmpBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opCompare(other: const &RuntimeTripleCmpBox)->s32
    {
        if .value < other.value do return -1
        if .value > other.value do return 1
        return 0
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCompare(other: s32)->s32
    {
        if .value < other do return -1
        if .value > other do return 1
        return 0
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCompare(other: u64)->s32
    {
        let self64 = cast(u64) .value
        if self64 < other do return -1
        if self64 > other do return 1
        return 0
    }
}

// Test: struct-struct comparison
#test
{
    var a = RuntimeTripleCmpBox{value: 5}
    var b = RuntimeTripleCmpBox{value: 10}

    @assert(a < b)
    @assert(b > a)
    @assert((a <=> b) == -1)
    @assert((b <=> a) == 1)
    @assert((a <=> a) == 0)
}

// Test: struct-s32 comparison
#test
{
    var box = RuntimeTripleCmpBox{value: 7}

    @assert(box < 10's32)
    @assert(box > 3's32)
    @assert(box >= 7's32)
    @assert(box <= 7's32)
}

// Test: struct-u64 comparison
#test
{
    var box = RuntimeTripleCmpBox{value: 50}

    @assert(box < 100'u64)
    @assert(box > 10'u64)
    @assert((box <=> 50'u64) == 0)
}
