#global private
using Swag

// Compare the real page predicate with division over every byte in a small page,
// every size class, and the end of the largest page. Interior and out-of-range
// addresses must remain invalid even when the inverse multiplication wraps.
#test
{
    for classIndex in AllocatorClassCount
    {
        let size = Allocator.classSize(classIndex)
        var page: AllocatorPage
        page.setupBlockDivision(cast(u32) size)
        page.areaStart = 0x1_0000_0000
        page.areaEnd   = page.areaStart + (512 * 1024 / size) * size

        for offset in 65536'u64
        {
            let address = page.areaStart + offset
            Swag.assert(page.isBlockAddress(address) == (address < page.areaEnd and offset % size == 0))
        }

        let lastBlock = page.areaEnd - size
        Swag.assert(page.isBlockAddress(lastBlock))
        Swag.assert(not page.isBlockAddress(lastBlock + 1))
        Swag.assert(not page.isBlockAddress(page.areaStart - 1))
        Swag.assert(not page.isBlockAddress(page.areaEnd))
        Swag.assert(not page.isBlockAddress(page.areaEnd + size))
    }
}
