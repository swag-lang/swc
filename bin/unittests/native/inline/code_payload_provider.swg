#global internal

namespace InlineCodePayload
{
    // The macro is called qualified, as 'Debug.safetyBoundCheck' is: the '#code' argument is then
    // analyzed in place, inside the inline frame, before the macro expands it.
    #[Swag.NoCopy]
    struct(T) Store
    {
        buffer: [*] T?
        count:  u64
    }

    impl Store
    {
        #[Swag.Inline]
        mtd opIndexSet(index: u64, value: T)
        {
            InlineCodePayloadDebug.bound(index < .count, "index out of range")
            let buffer = .buffer!
            buffer[index] = value
        }

        #[Swag.Inline]
        mtd opIndexPtr(index: u64)->*T
        {
            InlineCodePayloadDebug.bound(index < .count, "index out of range")
            let buffer = .buffer!
            return buffer + index
        }
    }

    struct Entry
    {
        length: u16
        prefix: u16
        suffix: u8
    }
}
