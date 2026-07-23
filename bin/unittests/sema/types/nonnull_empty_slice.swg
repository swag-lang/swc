#global private

struct SemaPresentEmptySliceDefault
{
    value: const [..] u8 = ""
}

const SEMA_PRESENT_EMPTY_STRING_SLICE: const [..] u8                 = ""
const SEMA_PRESENT_EMPTY_CSTRING: const cstring                      = cast(const cstring) @dataof("")
const SEMA_PRESENT_EMPTY_CSTRING_SLICE: const [..] u8                = cast(const [..] u8) SEMA_PRESENT_EMPTY_CSTRING
const SEMA_PRESENT_EMPTY_SLICE_DEFAULT: SemaPresentEmptySliceDefault = {}
const SEMA_MISSING_EMPTY_SLICE: #null const [..] u8                  = null

#assert(@countof(SEMA_PRESENT_EMPTY_STRING_SLICE) == 0)
#assert(@dataof(SEMA_PRESENT_EMPTY_STRING_SLICE) != null)
#assert(@countof(SEMA_PRESENT_EMPTY_CSTRING_SLICE) == 0)
#assert(@dataof(SEMA_PRESENT_EMPTY_CSTRING_SLICE) != null)
#assert(@countof(SEMA_PRESENT_EMPTY_SLICE_DEFAULT.value) == 0)
#assert(@dataof(SEMA_PRESENT_EMPTY_SLICE_DEFAULT.value) != null)

func semaPresentEmptySlices()
{
    let direct:      const [..] u8 = ""
    let ctext:       const cstring = cast(const cstring) @dataof("")
    let fromCString: const [..] u8 = cast(const [..] u8) ctext
    var fromDefault: SemaPresentEmptySliceDefault

    #assert(#typeof(direct) == const [..] u8)
    #assert(#typeof(fromCString) == const [..] u8)
    #assert(#typeof(fromDefault.value) == const [..] u8)
}
