#global fileprivate

var A: #null const bool     // swc-expected-error {{sema_err_bad_type_qualifier}}
var B: const bool           // swc-expected-error {{sema_err_bad_type_qualifier}}
var C: #null bool           // swc-expected-error {{sema_err_bad_type_qualifier}}

var D0: const *s32
var D1: const [..] s32
var D2: const [*] s32
var D3: const [2] s32

#assert(#typeof(D3) == const [2] s32)

var E0: #null *s32
var E1: #null [..] s32
var E2: #null [*] s32
var E3: #null any
var E4: #null string
var E5: #null cstring
var E6: #null typeinfo = null

#assert(#typeof(E6) == #null typeinfo)

func widenNullablePointer(value: *s32)->#null *s32 => value
func widenNullableString(value: string)->#null string => value
func widenNullableSlice(value: [..] s32)->#null [..] s32 => value
func widenNullableAny(value: any)->#null any => value
func widenNullableCString(value: cstring)->#null cstring => value
func widenNullableTypeInfo(value: typeinfo)->#null typeinfo => value

func acceptNullablePointer(value: #null *s32) {}
func acceptNullableString(value: #null string) {}
func acceptNullableSlice(value: #null [..] s32) {}
func acceptNullableAny(value: #null any) {}
func acceptNullableCString(value: #null cstring) {}
func acceptNullableTypeInfo(value: #null typeinfo) {}

#test
{
    var storage: s32 = 7
    let ptr: *s32 = &storage
    let nullablePtr: #null *s32 = ptr
    let widenedPtr: #null *s32 = widenNullablePointer(ptr)
    acceptNullablePointer(ptr)
    acceptNullablePointer(widenedPtr)

    let text: string = "abc"
    let nullableText: #null string = text
    let widenedText: #null string = widenNullableString(text)
    acceptNullableString(text)
    acceptNullableString(widenedText)

    let values: [3] s32 = [1, 2, 3]
    let slice: [..] s32 = values
    let nullableSlice: #null [..] s32 = slice
    let widenedSlice: #null [..] s32 = widenNullableSlice(slice)
    acceptNullableSlice(slice)
    acceptNullableSlice(widenedSlice)

    let boxed: any = 123
    let nullableAny: #null any = boxed
    let widenedAny: #null any = widenNullableAny(boxed)
    acceptNullableAny(boxed)
    acceptNullableAny(widenedAny)

    let cstr: cstring = cast(cstring) @dataof("abc")
    let nullableCstr: #null cstring = cstr
    let widenedCstr: #null cstring = widenNullableCString(cstr)
    acceptNullableCString(cstr)
    acceptNullableCString(widenedCstr)

    let info: typeinfo = s32
    let nullableInfo: #null typeinfo = info
    let widenedInfo: #null typeinfo = widenNullableTypeInfo(info)
    acceptNullableTypeInfo(info)
    acceptNullableTypeInfo(widenedInfo)

    @assert(nullablePtr == ptr)
    @assert(nullableText != null)
    @assert(@countof(nullableText) == @countof(text))
    @assert(@countof(nullableSlice) == 3)
    @assert(nullableAny != null)
    @assert(nullableCstr != null)
    @assert(@countof(nullableCstr) == 3)
    @assert(nullableInfo == s32)
}

namespace NS {}
const F: const NS // swc-expected-error {{sema_err_not_type}}
