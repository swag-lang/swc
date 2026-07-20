#global public
using Core

struct ImageMetaData
{
    sig:       u32
    tag:       Array'u8
    value:     Array'u8
}

impl ImageMetaData
{
    mtd const opCompare(other: ImageMetaData)->s32
    {
        let sigCmp = .sig <=> other.sig
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

    // Returns true if the metadata has the tag 'val'
    mtd const isTag(val: #nonull const [..] u8)->bool
    {
        if @countof(val) != .tag.count do
            return false
        return Memory.compare(@dataof(val), .tag.buffer, @countof(val)) == 0
    }

    // Convert the value to a slice
    mtd const toSlice()->#nonull const [..] u8
    {
        return .value.toSlice()
    }
}
