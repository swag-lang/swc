#global private

// Expressions
var c = ("foo").count

var _01 = Swag.getContext()
var _06 = Swag.args()
var _07 = Swag.jit()
var _09 = Swag.runtimeFlags()
var _10 = Swag.processInfos()
var _11 = Swag.modules()
var _12 = Swag.gvtd()
var _13 = Swag.compiler()

var _14 = Swag.kindOf(a)
var _16 = a.count
var _17 = a.buffer
var _23 = Swag.abs(a)
var _24 = Swag.sqrt(a)
var _25 = Swag.sin(a)
var _26 = Swag.cos(a)
var _27 = Swag.tan(a)
var _28 = Swag.sinh(a)
var _29 = Swag.cosh(a)
var _30 = Swag.tanh(a)
var _31 = Swag.asin(a)
var _32 = Swag.acos(a)
var _33 = Swag.atan(a)
var _34 = Swag.log(a)
var _35 = Swag.log2(a)
var _36 = Swag.log10(a)
var _37 = Swag.floor(a)
var _38 = Swag.ceil(a)
var _39 = Swag.trunc(a)
var _40 = Swag.round(a)
var _41 = Swag.exp(a)
var _42 = Swag.exp2(a)
var _43 = Swag.byteSwap(a)
var _44 = Swag.bitCountNz(a)
var _45 = Swag.bitCountTz(a)
var _46 = Swag.bitCountLz(a)

var _47 = Swag.makeSlice(a, b)
var _49 = Swag.makeString(a, b)
var _50 = Swag.makeAny(a, b)
var _54 = Swag.typeIs(a, b)
var _55 = Swag.tableOf(a, b)
var _56 = Swag.min(a, b)
var _57 = Swag.max(a, b)
var _58 = Swag.rol(a, b)
var _59 = Swag.ror(a, b)
var _60 = Swag.pow(a, b)
var _61 = Swag.atan2(a, b)
var _62 = Swag.atomxchg(a, b)
var _63 = Swag.atomxor(a, b)
var _64 = Swag.atomor(a, b)
var _65 = Swag.atomand(a, b)
var _66 = Swag.atomadd(a, b)

var _67 = Swag.makeInterface(a, b, c)
var _69 = Swag.typeAs(a, b, c)
var _70 = Swag.atomcmpxchg(a, b, c)
var _71 = Swag.typeCmp(a, b, c)
var _72 = Swag.muladd(a, b, c)

var _75 = Swag.memcmp(a, b, c)

// Statements
func test()
{
    Swag.breakpoint()

    Swag.assert(a)
    Swag.panic(a, b)
    Swag.setContext(a)

    Swag.compilerError(a, b)
    Swag.compilerWarning(a, b)
    Swag.atomadd(a, b)

    Swag.print("foo")
    Swag.print("foo", "bar", 1, 2)

    Swag.memcpy(a, b, c)
    Swag.memmove(a, b, c)
    Swag.memset(a, b, c)
    let a = Swag.memcmp(a, b, c)
    let a = Swag.stringCmp(a, b)

    Swag.init(a)
    Swag.drop(a)
    Swag.postCopy(a)
    Swag.postMove(a)
}
