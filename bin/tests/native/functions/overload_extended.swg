#global fileprivate

// Overload with different parameter counts (0, 1, 2)
var gArityResult: s32 = 0

func arity() { gArityResult = 0 }
func arity(a: s32) { gArityResult = a }
func arity(a: s32, b: s32) { gArityResult = a + b }

#test
{
    arity()
    @assert(gArityResult == 0)
    arity(10)
    @assert(gArityResult == 10)
    arity(10, 20)
    @assert(gArityResult == 30)
}

// Method overload with different param types (using explicit suffixes)
struct OverS {}

var gOverMethodS32: s32 = 0
var gOverMethodBool: bool = false
var gOverMethodStr: string

impl OverS
{
    mtd process(a: s32) { gOverMethodS32 = a }
    mtd process(a: bool) { gOverMethodBool = a }
    mtd process(a: string) { gOverMethodStr = a }
}

#test
{
    var s: OverS
    gOverMethodS32 = 0
    gOverMethodBool = false
    gOverMethodStr = ""
    s.process(42's32)
    s.process(true)
    s.process("hello")
    @assert(gOverMethodS32 == 42)
    @assert(gOverMethodBool == true)
    @assert(gOverMethodStr == "hello")
}

// Overload with u8 vs u32 (explicit type suffixes needed)
var gOverU8: u8 = 0
var gOverU32: u32 = 0

func sizedOp(a: u8) { gOverU8 = a }
func sizedOp(a: u32) { gOverU32 = a }

#test
{
    gOverU8 = 0
    gOverU32 = 0
    sizedOp(5'u8)
    sizedOp(1000'u32)
    @assert(gOverU8 == 5)
    @assert(gOverU32 == 1000)
}

// Overload with pointer vs value
var gOverPtrVal: s32 = 0

func ptrOrVal(a: s32) { gOverPtrVal = a }
func ptrOrVal(a: *s32) { gOverPtrVal = dref a }

#test
{
    gOverPtrVal = 0
    ptrOrVal(42)
    @assert(gOverPtrVal == 42)
    var x = 99
    ptrOrVal(&x)
    @assert(gOverPtrVal == 99)
}

// Overloaded function as callback
func applyOp(a: s32, b: s32, op: func(s32, s32)->s32)->s32
{
    return op(a, b)
}

func combine(a: s32, b: s32)->s32 { return a + b }

#test
{
    let result = applyOp(3, 4, &combine)
    @assert(result == 7)
}

// Method overload via static call
struct MOverS {}
var gMOver0: s32 = 0
var gMOver1: s32 = 0
impl MOverS
{
    mtd doIt() { gMOver0 += 1 }
    mtd doIt(a: s32) { gMOver1 = a }
}

#test
{
    var s: MOverS
    gMOver0 = 0
    gMOver1 = 0
    s.doIt()
    s.doIt(42)
    @assert(gMOver0 == 1)
    @assert(gMOver1 == 42)
    // Static call style
    MOverS.doIt(&s)
    MOverS.doIt(&s, 99)
    @assert(gMOver0 == 2)
    @assert(gMOver1 == 99)
}

// Overload: bool vs s32 (bool is distinct from integer)
var gBoolHit: bool = false
var gIntHit: s32 = 0

func boolOrInt(a: bool) { gBoolHit = a }
func boolOrInt(a: s32)  { gIntHit = a }

#test
{
    gBoolHit = false
    gIntHit = 0
    boolOrInt(true)
    boolOrInt(42's32)
    @assert(gBoolHit == true)
    @assert(gIntHit == 42)
}
