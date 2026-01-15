// Expressions
var a = @strlen()                       // swc-expected-error {{parser_err_too_few_arguments}}
var b = @strlen(a, b + 4)               // swc-expected-error {{parser_err_too_many_arguments}}
var c = @strlen("foo")

var _01 = @getcontext()
var _02 = @getcontext(a)                // swc-expected-error {{parser_err_too_many_arguments}}
var _03 = @dbgalloc()
var _04 = @sysalloc()
var _05 = @err()
var _06 = @args()
var _07 = @bytecode()
var _08 = @index()
var _09 = @rtflags()
var _10 = @pinfos()
var _11 = @modules()
var _12 = @gvtd()
var _13 = @compiler()

var _14 = @kindof(a)
var _15 = @kindof()                     // swc-expected-error {{parser_err_too_few_arguments}}
var _16 = @countof(a)
var _17 = @dataof(a)
var _18 = @cvastart(a)
var _19 = @cvaend(a)
var _20 = @mkcallback(a)
var _21 = @alloc(a)
var _22 = @free(a)
var _23 = @abs(a)
var _24 = @sqrt(a)
var _25 = @sin(a)
var _26 = @cos(a)
var _27 = @tan(a)
var _28 = @sinh(a)
var _29 = @cosh(a)
var _30 = @tanh(a)
var _31 = @asin(a)
var _32 = @acos(a)
var _33 = @atan(a)
var _34 = @log(a)
var _35 = @log2(a)
var _36 = @log10(a)
var _37 = @floor(a)
var _38 = @ceil(a)
var _39 = @trunc(a)
var _40 = @round(a)
var _41 = @exp(a)
var _42 = @exp2(a)
var _43 = @byteswap(a)
var _44 = @bitcountnz(a)
var _45 = @bitcounttz(a)
var _46 = @bitcountlz(a)

var _47 = @mkslice(a, b)
var _48 = @mkslice(a)                   // swc-expected-error {{parser_err_too_few_arguments}}
var _49 = @mkstring(a, b)
var _50 = @mkany(a, b)
var _51 = @cvaarg(a, b)
var _52 = @realloc(a, b)
var _54 = @is(a, b)
var _55 = @tableof(a, b)
var _56 = @min(a, b)
var _57 = @max(a, b)
var _58 = @rol(a, b)
var _59 = @ror(a, b)
var _60 = @pow(a, b)
var _61 = @atan2(a, b)
var _62 = @atomxchg(a, b)
var _63 = @atomxor(a, b)
var _64 = @atomor(a, b)
var _65 = @atomand(a, b)
var _66 = @atomadd(a, b)

var _67 = @mkinterface(a, b, c)
var _68 = @mkinterface(a, b)            // swc-expected-error {{parser_err_too_few_arguments}}
var _69 = @as(a, b, c)
var _70 = @atomcmpxchg(a, b, c)
var _71 = @typecmp(a, b, c)
var _72 = @muladd(a, b, c)

var _73 = @strcmp("a", "b")
var _74 = @strcmp("a")                  // swc-expected-error {{parser_err_too_few_arguments}}
var _75 = @memcmp(a, b, c)
var _76 = @memcmp(a, b)                 // swc-expected-error {{parser_err_too_few_arguments}}

// Statements
func test()
{
    @breakpoint()
    @breakpoint(a)                      // swc-expected-error {{parser_err_too_many_arguments}}

    @assert(a)
    @assert()                           // swc-expected-error {{parser_err_too_few_arguments}}
    @cvastart(a)
    @cvaend(a)
    @panic(a, b)
    @setcontext(a)

    @compilererror(a, b)
    @compilererror(a)                   // swc-expected-error {{parser_err_too_few_arguments}}
    @compilerwarning(a, b)
    @atomadd(a, b)

    @print("foo")
    @print("foo", "bar", 1, 2)
    @print()                            // swc-expected-error {{parser_err_too_few_arguments}}

    @free(a)
    @memcpy(a, b, c)
    @memcpy(a, b)                       // swc-expected-error {{parser_err_too_few_arguments}}
    @memmove(a, b, c)
    @memset(a, b, c)
    let a = @memcmp(a, b, c)
    let a = @strcmp(a, b)
    let a = @stringcmp(a, b)

    @init(a)
    @drop(a)
    @postcopy(a)
    @postmove(a)
}
