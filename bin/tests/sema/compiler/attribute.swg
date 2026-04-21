#global fileprivate

attr MyAttr();

#[MyAttr]
var A: s32 = 0

#[MyAttr]
{
    var B: s32 = 0
    var C: s32 = 0
}

const BB = 1
const CC = 0

attr Foreign1(module: string, function: string = "")
attr Foreign3(module: s32...)

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

attr VariadicSigned(a: s8...)
attr VariadicUnsigned(a: u8...)
attr VariadicString(a: string...)

attr Over(a: s8)
attr Over(a: s16)

attr MatchCallFixed(a: s32, b: string = "")
attr MatchCallVariadic(a: s32...)
enum AttrAutoScopeMode: u8
{
    A
    B
}
attr AttrAutoScope(mode: AttrAutoScopeMode)

#[Swag.EnumFlags]
enum AttrAutoScopeFlags: u8
{
    A
    B
}
attr AttrAutoScopeFlag(mode: AttrAutoScopeFlags)

#[MatchCallFixed(1)]
var MatchCallOk1: s32 = 0

#[MatchCallFixed(a: 1, b: "x")]
var MatchCallOk2: s32 = 0

#[MatchCallVariadic(1, 2, 3)]
var MatchCallOk3: s32 = 0

#test
{
    #[AttrAutoScope(.B)]
    var V: s32 = 0
}

#test
{
    #[AttrAutoScopeFlag(.A | .B)]
    var V: s32 = 0
}
