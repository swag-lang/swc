#global public

using Core

// Stores one opaque metadata record associated with an image.
//
// Codecs use `signature` and `tag` to identify a record and keep `value` as its
// format-specific byte payload. Unknown records can therefore survive a
// decode/encode round trip without Pixel interpreting their contents.
//
// Structured TagBin payloads are decoded through the statically requested type, so the
// source type name is not part of this record's persisted identity.
struct ImageMetadata
{
    public
    {
        #[Core.Serialization.Key("signature")]
        signature: u32     // Codec-defined signature or namespace identifier.

        #[Core.Serialization.Key("tag")]
        tag: Array'u8     // Owned byte tag that identifies the record within `signature`.

        #[Core.Serialization.Key("value")]
        value: Array'u8     // Owned, codec-defined payload bytes.
    }
}

impl ImageMetadata
{
    // Compares metadata lexicographically by signature, tag, then value.
    mtd const opCompare(other: ImageMetadata)->s32
    {
        let sigCmp = .signature <=> other.signature
        if sigCmp do
            return sigCmp

        let tagCount = Math.min(.tag.count, other.tag.count)
        if tagCount
        {
            let tagCmp = Memory.compare(.tag.buffer, other.tag.buffer, tagCount)
            if tagCmp do
                return tagCmp
        }

        let tagLenCmp = .tag.count <=> other.tag.count
        if tagLenCmp do
            return tagLenCmp

        let valueCount = Math.min(.value.count, other.value.count)
        if valueCount
        {
            let valueCmp = Memory.compare(.value.buffer, other.value.buffer, valueCount)
            if valueCmp do
                return valueCmp
        }

        return .value.count <=> other.value.count
    }

    // Reports whether the tag exactly matches `val`, including its length.
    mtd const isTag(val: const [..] u8)->bool
    {
        if val.count != .tag.count do
            return false
        return Memory.compare(val.buffer, .tag.buffer, val.count) == 0
    }

    // Borrows the metadata value as a read-only slice.
    //
    // The slice remains valid until this record is mutated or released.
    mtd const toSlice()->const [..] u8
    {
        return .value.toSlice()
    }
}
