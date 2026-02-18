#global internal

attr MyAttr();

#[MyAttr]
var A: s32 = 0

#[MyAttr]
{
    var B: s32 = 0
    var C: s32 = 0
}

const BB = 1
#[BB] // swc-expected-error {{sema_err_not_attribute}}
const CC = 0

attr Foreign1(module: string, function: string = "")
attr Foreign3(module: s32...)

attr Foreign2(module: any)              // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
attr Foreign4(module: ..., x: s32)      // swc-expected-error {{sema_err_invalid_attribute_parameter_type}}
attr Foreign5(module: s32..., x: s32)   // swc-expected-error {{sema_err_variadic_not_last}}
attr Default1(x: s32 = 0, y: s32)       // swc-expected-error {{sema_err_parameter_default_value_not_last}}

attr Default2(x: s32, x: bool)  // swc-expected-error {{sema_err_already_defined}}

attr AttrSignedInts1(a: s8)
attr AttrSignedInts2(a: s8, b: s16, c: s32, d: s64)

attr AttrUnsignedInts1(a: u8)
attr AttrUnsignedInts2(a: u8, b: u16, c: u32, d: u64)

attr AttrMixedInts(a: s8, b: u8, c: s16, d: u16, e: s32, f: u32)

attr AttrStrings(a: string)
attr AttrStringRune(a: string, b: rune)
attr AttrTypeInfo(t: typeinfo)
attr AttrAllKinds(a: s8, b: u8, c: string, d: rune, e: typeinfo)

attr DefaultOkInt1(x: s8 = 0)
attr DefaultOkInt2(x: s16, y: u8 = 1)
attr DefaultOkString(x: string = "")
attr DefaultOkRune(ch: rune = 'a')
attr DefaultOkMixed(a: s8, b: string = "", c: rune = 'x')

attr ValidFloat32(x: f32)
attr ValidFloat64(x: f64)
attr ValidMixed1(a: s8, b: f32)
attr ValidMixed2(a: string, b: f64)
attr ValidVariadicFloat(x: f32...)

attr DefaultBadInt8(a: s8 = 0, b: s16)           // swc-expected-error {{sema_err_parameter_default_value_not_last}}
attr DefaultBadString(a: string = "", b: rune)   // swc-expected-error {{sema_err_parameter_default_value_not_last}}

attr VariadicSigned(a: s8...)
attr VariadicUnsigned(a: u8...)
attr VariadicString(a: string...)

attr VariadicNotLast1(a: s8..., b: s16)      // swc-expected-error {{sema_err_variadic_not_last}}
attr VariadicNotLast2(a: string..., b: s32)  // swc-expected-error {{sema_err_variadic_not_last}}

attr Over(a: s8)
attr Over(a: s16)

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
attr Over1(a: s8)
attr Over1(a: s8)

attr MatchCallFixed(a: s32, b: string = "")
attr MatchCallVariadic(a: s32...)
enum AttrAutoScopeMode: u8
{
    A
    B
}
attr AttrAutoScope(mode: AttrAutoScopeMode)

#[MatchCallFixed(1)]
var MatchCallOk1: s32 = 0

#[MatchCallFixed(a: 1, b: "x")]
var MatchCallOk2: s32 = 0

#[MatchCallVariadic(1, 2, 3)]
var MatchCallOk3: s32 = 0

#test
{
    #[MatchCallFixed] // swc-expected-error {{sema_err_too_few_arguments}}
    var V: s32 = 0
}

#test
{
    #[MatchCallFixed(1, "x", 2)] // swc-expected-error {{sema_err_too_many_arguments}}
    var V: s32 = 0
}

#test
{
    #[MatchCallFixed("x")] // swc-expected-error {{sema_err_cannot_cast}}
    var V: s32 = 0
}

#test
{
    #[MatchCallFixed(c: 1)] // swc-expected-error {{sema_err_named_argument_unknown}}
    var V: s32 = 0
}

#test
{
    #[MatchCallFixed(a: 1, a: 2)] // swc-expected-error {{sema_err_named_argument_duplicate}}
    var V: s32 = 0
}

#test
{
    #[MatchCallFixed(a: 1, 2)] // swc-expected-error {{sema_err_unnamed_parameter}}
    var V: s32 = 0
}

#test
{
    #[AttrAutoScope(.B)]
    var V: s32 = 0
}

#test
{
    #[AttrAutoScope(.C)] // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
    var V: s32 = 0
}
