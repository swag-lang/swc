#global private

struct NativePresentEmptySliceDefault
{
    value: const [..] u8 = ""
}

const NATIVE_PRESENT_EMPTY_STRING_SLICE:  const [..] u8                  = ""
const NATIVE_PRESENT_EMPTY_CSTRING:       const cstring                  = cast(const cstring) ("").buffer
const NATIVE_PRESENT_EMPTY_CSTRING_SLICE: const [..] u8                  = cast(const [..] u8) NATIVE_PRESENT_EMPTY_CSTRING
const NATIVE_PRESENT_EMPTY_SLICE_DEFAULT: NativePresentEmptySliceDefault = {}
const NATIVE_MISSING_EMPTY_SLICE:         #null const [..] u8            = null

func nativePresentEmptySlices()->bool
{
    let direct:      const [..] u8 = ""
    let ctext:       const cstring = cast(const cstring) ("").buffer
    let fromCString: const [..] u8 = cast(const [..] u8) ctext
    var fromDefault: NativePresentEmptySliceDefault

    return NATIVE_PRESENT_EMPTY_STRING_SLICE.count == 0 and
           NATIVE_PRESENT_EMPTY_STRING_SLICE.buffer != null and
           NATIVE_PRESENT_EMPTY_CSTRING_SLICE.count == 0 and
           NATIVE_PRESENT_EMPTY_CSTRING_SLICE.buffer != null and
           NATIVE_PRESENT_EMPTY_SLICE_DEFAULT.value.count == 0 and
           NATIVE_PRESENT_EMPTY_SLICE_DEFAULT.value.buffer != null and
           NATIVE_MISSING_EMPTY_SLICE.count == 0 and
           NATIVE_MISSING_EMPTY_SLICE.buffer == null and
           direct.count == 0 and
           direct.buffer != null and
           fromCString.count == 0 and
           fromCString.buffer != null and
           fromDefault.value.count == 0 and
           fromDefault.value.buffer != null
}

#test
{
    Swag.assert(nativePresentEmptySlices())
}
