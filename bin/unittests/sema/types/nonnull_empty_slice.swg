#global private

struct SemaPresentEmptySliceDefault
{
    value: const [..] u8 = ""
}

const SEMA_PRESENT_EMPTY_STRING_SLICE:  const [..] u8                = ""
const SEMA_PRESENT_EMPTY_CSTRING:       const cstring                = cast(const cstring) ("").buffer
const SEMA_PRESENT_EMPTY_CSTRING_SLICE: const [..] u8                = cast(const [..] u8) SEMA_PRESENT_EMPTY_CSTRING
const SEMA_PRESENT_EMPTY_SLICE_DEFAULT: SemaPresentEmptySliceDefault = {}
const SEMA_MISSING_EMPTY_SLICE:         const [..] u8?               = null

#assert(SEMA_PRESENT_EMPTY_STRING_SLICE.count == 0)
#assert(SEMA_PRESENT_EMPTY_STRING_SLICE.buffer != null)
#assert(SEMA_PRESENT_EMPTY_CSTRING_SLICE.count == 0)
#assert(SEMA_PRESENT_EMPTY_CSTRING_SLICE.buffer != null)
#assert(SEMA_PRESENT_EMPTY_SLICE_DEFAULT.value.count == 0)
#assert(SEMA_PRESENT_EMPTY_SLICE_DEFAULT.value.buffer != null)

func semaPresentEmptySlices()
{
    let direct:      const [..] u8 = ""
    let ctext:       const cstring = cast(const cstring) ("").buffer
    let fromCString: const [..] u8 = cast(const [..] u8) ctext
    var fromDefault: SemaPresentEmptySliceDefault

    #assert(#typeof(direct) == const [..] u8)
    #assert(#typeof(fromCString) == const [..] u8)
    #assert(#typeof(fromDefault.value) == const [..] u8)
}
