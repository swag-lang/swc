#global private

struct NativePresentEmptySliceDefault
{
    value: #nonull const [..] u8 = ""
}

const NATIVE_PRESENT_EMPTY_STRING_SLICE: #nonull const [..] u8 = ""
const NATIVE_PRESENT_EMPTY_CSTRING: const cstring = cast(const cstring) @dataof("")
const NATIVE_PRESENT_EMPTY_CSTRING_SLICE: #nonull const [..] u8 = cast(const [..] u8) NATIVE_PRESENT_EMPTY_CSTRING
const NATIVE_PRESENT_EMPTY_SLICE_DEFAULT: NativePresentEmptySliceDefault = {}
const NATIVE_MISSING_EMPTY_SLICE: #null const [..] u8 = null

func nativePresentEmptySlices()->bool
{
    let direct: #nonull const [..] u8 = ""
    let ctext: const cstring = cast(const cstring) @dataof("")
    let fromCString: #nonull const [..] u8 = cast(const [..] u8) ctext
    var fromDefault: NativePresentEmptySliceDefault

    return @countof(NATIVE_PRESENT_EMPTY_STRING_SLICE) == 0 and
           @dataof(NATIVE_PRESENT_EMPTY_STRING_SLICE) != null and
           @countof(NATIVE_PRESENT_EMPTY_CSTRING_SLICE) == 0 and
           @dataof(NATIVE_PRESENT_EMPTY_CSTRING_SLICE) != null and
           @countof(NATIVE_PRESENT_EMPTY_SLICE_DEFAULT.value) == 0 and
           @dataof(NATIVE_PRESENT_EMPTY_SLICE_DEFAULT.value) != null and
           @countof(NATIVE_MISSING_EMPTY_SLICE) == 0 and
           @dataof(NATIVE_MISSING_EMPTY_SLICE) == null and
           @countof(direct) == 0 and
           @dataof(direct) != null and
           @countof(fromCString) == 0 and
           @dataof(fromCString) != null and
           @countof(fromDefault.value) == 0 and
           @dataof(fromDefault.value) != null
}

#test
{
    @assert(nativePresentEmptySlices())
}
