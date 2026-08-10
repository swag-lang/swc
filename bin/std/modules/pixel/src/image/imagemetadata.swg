#global public

using Core

// Stores one opaque metadata record associated with an image.
//
// Codecs use `signature` and `tag` to identify a record and keep `value` as its
// format-specific byte payload. Unknown records can therefore survive a
// decode/encode round trip without Pixel interpreting their contents.
//
// The aliases keep records written under the earlier spelling readable; see
// [[Pixel.Image]] for why a serialized rename needs one.
#[Core.Serialization.Alias("ImageMetaData")]
struct ImageMetadata
{
    public
    {
        #[Core.Serialization.Alias("sig")]
        signature: u32     // Codec-defined signature or namespace identifier.

        tag:   Array'u8     // Owned byte tag that identifies the record within `signature`.
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
        if @countof(val) != .tag.count do
            return false
        return Memory.compare(@dataof(val), .tag.buffer, @countof(val)) == 0
    }

    // Borrows the metadata value as a read-only slice.
    //
    // The slice remains valid until this record is mutated or released.
    mtd const toSlice()->const [..] u8
    {
        return .value.toSlice()
    }
}
