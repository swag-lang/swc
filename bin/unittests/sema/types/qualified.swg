#global private

#[Swag.Strict]
alias QualifiedStrictPtr = *s32

#[Swag.Strict]
alias QualifiedStrictSlice = [..] s32

#[Swag.Strict]
alias QualifiedStrictString = string

#[Swag.Strict]
alias QualifiedStrictCString = cstring

#[Swag.Strict]
alias QualifiedStrictTypeInfo = typeinfo

var D0: #null const *s32
var D1: #null const [..] s32
var D2: #null const [*] s32
var D3: const [2] s32
var D4: const QualifiedStrictPtr = undefined
var D5: const QualifiedStrictSlice = undefined

#assert(#typeof(D3) == const [2] s32)
#assert(#typeof(D4) == const *s32)
#assert(#typeof(D5) == const [..] s32)

func acceptConstAny(value: const any) {}
func widenConstAny(value: any)->const any => value

var E0:  #null *s32
var E1:  #null [..] s32
var E2:  #null [*] s32
var E3:  #null any
var E4:  #null string
var E5:  #null cstring
var E6:  #null typeinfo = null
var E7:  #null QualifiedStrictPtr
var E8:  #null QualifiedStrictSlice
var E9:  #null QualifiedStrictString
var E10: #null QualifiedStrictCString
var E11: #null QualifiedStrictTypeInfo = null

#assert(#typeof(E6) == #null typeinfo)
#assert(#typeof(E7) == #null *s32)
#assert(#typeof(E8) == #null [..] s32)
#assert(#typeof(E9) == #null string)
#assert(#typeof(E10) == #null cstring)
#assert(#typeof(E11) == #null typeinfo)

func widenNullablePointer(value: *s32)->#null *s32          => value
func widenNullableString(value: string)->#null string       => value
func widenNullableSlice(value: [..] s32)->#null [..] s32    => value
func widenNullableAny(value: any)->#null any                => value
func widenNullableCString(value: cstring)->#null cstring    => value
func widenNullableTypeInfo(value: typeinfo)->#null typeinfo => value

func acceptNullablePointer(value: #null *s32) {}
func acceptNullableString(value: #null string) {}
func acceptNullableSlice(value: #null [..] s32) {}
func acceptNullableAny(value: #null any) {}
func acceptNullableCString(value: #null cstring) {}
func acceptNullableTypeInfo(value: #null typeinfo) {}

func semaTest001()
{
    var storage:           s32 = 7
    let ptr:               *s32 = &storage
    var nullablePtr:       #null *s32 = ptr
    var nullableStrictPtr: #null QualifiedStrictPtr = cast(QualifiedStrictPtr) ptr
    let widenedPtr:        #null *s32 = widenNullablePointer(ptr)
    acceptNullablePointer(ptr)
    acceptNullablePointer(widenedPtr)

    let text:               string = "abc"
    let nullableText:       #null string = text
    var nullableStrictText: #null QualifiedStrictString = cast(QualifiedStrictString) text
    let widenedText:        #null string = widenNullableString(text)
    acceptNullableString(text)
    acceptNullableString(widenedText)

    let values:              [3] s32 = [1, 2, 3]
    let slice:               [..] s32 = values
    let nullableSlice:       #null [..] s32 = slice
    var nullableStrictSlice: #null QualifiedStrictSlice = cast(QualifiedStrictSlice) slice
    let widenedSlice:        #null [..] s32 = widenNullableSlice(slice)
    acceptNullableSlice(slice)
    acceptNullableSlice(widenedSlice)

    let boxed:           any = 123
    let nullableAny:     #null any = boxed
    let widenedAny:      #null any = widenNullableAny(boxed)
    let constAny:        const any = boxed
    let widenedConstAny: const any = widenConstAny(boxed)
    acceptNullableAny(boxed)
    acceptNullableAny(widenedAny)
    acceptConstAny(boxed)
    acceptConstAny(widenedConstAny)
    #assert(#typeof(constAny) == const any)

    var cstrData:           [4] u8 = ['a''u8, 'b''u8, 'c''u8, 0]
    let cstr:               cstring = cast(cstring) &cstrData[0]
    var nullableCstr:       #null cstring = cstr
    var nullableStrictCstr: #null QualifiedStrictCString = cast(QualifiedStrictCString) cstr
    let widenedCstr:        #null cstring = widenNullableCString(cstr)
    acceptNullableCString(cstr)
    acceptNullableCString(widenedCstr)

    let info:               typeinfo = s32
    let nullableInfo:       #null typeinfo = info
    var nullableStrictInfo: #null QualifiedStrictTypeInfo = cast(QualifiedStrictTypeInfo) info
    let widenedInfo:        #null typeinfo = widenNullableTypeInfo(info)
    acceptNullableTypeInfo(info)
    acceptNullableTypeInfo(widenedInfo)

    @assert(nullablePtr == ptr)
    @assert(nullableStrictPtr == ptr)
    @assert(nullableText == text)
    @assert(text == nullableText)
    @assert(nullableText != null)
    @assert(nullableStrictText != null)
    @assert(@countof(nullableText) == @countof(text))
    @assert(@countof(nullableSlice) == 3)
    @assert(@countof(nullableStrictSlice) == 3)
    @assert(nullableAny != null)
    @assert(nullableCstr != null)
    @assert(nullableStrictCstr != null)
    @assert(@countof(nullableCstr) == 3)
    @assert(nullableInfo == s32)
    @assert(nullableStrictInfo == s32)

    // The '#null' qualifiers above are real: null flows into every widened local.
    nullablePtr         = null
    nullableStrictPtr   = null
    nullableCstr        = null
    nullableStrictCstr  = null
    nullableStrictText  = null
    nullableStrictSlice = null
    nullableStrictInfo  = null
}

namespace NS {}
