#global private

struct JitPresentEmptySliceDefault
{
    value: const [..] u8 = ""
}

const JIT_PRESENT_EMPTY_STRING_SLICE: const [..] u8 = ""
const JIT_PRESENT_EMPTY_CSTRING: const cstring = cast(const cstring) @dataof("")
const JIT_PRESENT_EMPTY_CSTRING_SLICE: const [..] u8 = cast(const [..] u8) JIT_PRESENT_EMPTY_CSTRING
const JIT_PRESENT_EMPTY_SLICE_DEFAULT: JitPresentEmptySliceDefault = {}
const JIT_MISSING_EMPTY_SLICE: #null const [..] u8 = null

func jitPresentEmptySlices()->bool
{
    let direct: const [..] u8 = ""
    let ctext: const cstring = cast(const cstring) @dataof("")
    let fromCString: const [..] u8 = cast(const [..] u8) ctext
    var fromDefault: JitPresentEmptySliceDefault

    return @countof(JIT_PRESENT_EMPTY_STRING_SLICE) == 0 and
           @dataof(JIT_PRESENT_EMPTY_STRING_SLICE) != null and
           @countof(JIT_PRESENT_EMPTY_CSTRING_SLICE) == 0 and
           @dataof(JIT_PRESENT_EMPTY_CSTRING_SLICE) != null and
           @countof(JIT_PRESENT_EMPTY_SLICE_DEFAULT.value) == 0 and
           @dataof(JIT_PRESENT_EMPTY_SLICE_DEFAULT.value) != null and
           @countof(JIT_MISSING_EMPTY_SLICE) == 0 and
           @dataof(JIT_MISSING_EMPTY_SLICE) == null and
           @countof(direct) == 0 and
           @dataof(direct) != null and
           @countof(fromCString) == 0 and
           @dataof(fromCString) != null and
           @countof(fromDefault.value) == 0 and
           @dataof(fromDefault.value) != null
}

#test
{
    @assert(jitPresentEmptySlices())
}
