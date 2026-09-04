#global private

#[Swag.Strict]
alias QualifiedStrictPtr      = *s32

#[Swag.Strict]
alias QualifiedStrictSlice    = [..] s32

#[Swag.Strict]
alias QualifiedStrictString   = string

#[Swag.Strict]
alias QualifiedStrictCString  = cstring

#[Swag.Strict]
alias QualifiedStrictTypeInfo = typeinfo

var D0: const *s32?
var D1: const [..] s32?
var D2: const [*] s32?
var D3: const [2] s32

#assert(#typeof(D3) == const [2] s32)
#assert(#fullnameof(#type const QualifiedStrictPtr) == "const *s32")
#assert(#fullnameof(#type const QualifiedStrictSlice) == "const [..] s32")

func acceptConstAny(value: const any) {}
func widenConstAny(value: any)->const any => value

var E0:  *s32?
var E1:  [..] s32?
var E2:  [*] s32?
var E3:  any?
var E4:  string?
var E5:  cstring?
var E6:  typeinfo?                = null
var E7:  QualifiedStrictPtr?
var E8:  QualifiedStrictSlice?
var E9:  QualifiedStrictString?
var E10: QualifiedStrictCString?
var E11: QualifiedStrictTypeInfo? = null

#assert(#typeof(E6) == typeinfo?)
#assert(#typeof(E7) == *s32?)
#assert(#typeof(E8) == [..] s32?)
#assert(#typeof(E9) == string?)
#assert(#typeof(E10) == cstring?)
#assert(#typeof(E11) == typeinfo?)

func widenNullablePointer(value: *s32)->*s32?          => value
func widenNullableString(value: string)->string?       => value
func widenNullableSlice(value: [..] s32)->[..] s32?    => value
func widenNullableAny(value: any)->any?                => value
func widenNullableCString(value: cstring)->cstring?    => value
func widenNullableTypeInfo(value: typeinfo)->typeinfo? => value

func acceptNullablePointer(value: *s32?) {}
func acceptNullableString(value: string?) {}
func acceptNullableSlice(value: [..] s32?) {}
func acceptNullableAny(value: any?) {}
func acceptNullableCString(value: cstring?) {}
func acceptNullableTypeInfo(value: typeinfo?) {}

func semaTest001()
{
    var storage:           s32                 = 7
    let ptr:               *s32                = &storage
    var nullablePtr:       *s32?               = ptr
    var nullableStrictPtr: QualifiedStrictPtr? = cast(QualifiedStrictPtr) ptr
    let widenedPtr:        *s32?               = widenNullablePointer(ptr)
    acceptNullablePointer(ptr)
    acceptNullablePointer(widenedPtr)

    let text:               string                 = "abc"
    let nullableText:       string?                = text
    var nullableStrictText: QualifiedStrictString? = cast(QualifiedStrictString) text
    let widenedText:        string?                = widenNullableString(text)
    acceptNullableString(text)
    acceptNullableString(widenedText)

    let values:              [3] s32               = [1, 2, 3]
    let slice:               [..] s32              = values
    let nullableSlice:       [..] s32?             = slice
    var nullableStrictSlice: QualifiedStrictSlice? = cast(QualifiedStrictSlice) slice
    let widenedSlice:        [..] s32?             = widenNullableSlice(slice)
    acceptNullableSlice(slice)
    acceptNullableSlice(widenedSlice)

    let boxed:           any       = 123
    let nullableAny:     any?      = boxed
    let widenedAny:      any?      = widenNullableAny(boxed)
    let constAny:        const any = boxed
    let widenedConstAny: const any = widenConstAny(boxed)
    acceptNullableAny(boxed)
    acceptNullableAny(widenedAny)
    acceptConstAny(boxed)
    acceptConstAny(widenedConstAny)
    #assert(#typeof(constAny) == const any)

    var cstrData:           [4] u8                  = ['a'u8, 'b'u8, 'c'u8, 0]
    let cstr:               cstring                 = cast(cstring) &cstrData[0]
    var nullableCstr:       cstring?                = cstr
    var nullableStrictCstr: QualifiedStrictCString? = cast(QualifiedStrictCString) cstr
    let widenedCstr:        cstring?                = widenNullableCString(cstr)
    acceptNullableCString(cstr)
    acceptNullableCString(widenedCstr)

    let info:               typeinfo                 = s32
    let nullableInfo:       typeinfo?                = info
    var nullableStrictInfo: QualifiedStrictTypeInfo? = cast(QualifiedStrictTypeInfo) info
    let widenedInfo:        typeinfo?                = widenNullableTypeInfo(info)
    acceptNullableTypeInfo(info)
    acceptNullableTypeInfo(widenedInfo)

    Swag.assert(nullablePtr == ptr)
    Swag.assert(nullableStrictPtr == ptr)
    Swag.assert(nullableText == text)
    Swag.assert(text == nullableText)
    Swag.assert(nullableText != null)
    Swag.assert(nullableStrictText != null)
    Swag.assert(nullableText.count == text.count)
    Swag.assert(nullableSlice.count == 3)
    Swag.assert(nullableStrictSlice.count == 3)
    Swag.assert(nullableAny != null)
    Swag.assert(nullableCstr != null)
    Swag.assert(nullableStrictCstr != null)
    Swag.assert(nullableCstr.count == 3)
    Swag.assert(nullableInfo == s32)
    Swag.assert(nullableStrictInfo == s32)

    // The '?' qualifiers above are real: null flows into every widened local.
    nullablePtr         = null
    nullableStrictPtr   = null
    nullableCstr        = null
    nullableStrictCstr  = null
    nullableStrictText  = null
    nullableStrictSlice = null
    nullableStrictInfo  = null
}

namespace NS {}
