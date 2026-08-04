using Core

struct BlockMapping
{
    logical:  u64
    physical: u64
}

struct Node
{
    id:             u64
    parentId:       u64
    name:           String
    attributes:     u32
    size:           u64
    creationTime:   u64
    lastAccessTime: u64
    lastWriteTime:  u64
    changeTime:     u64
    blocks:         Array'BlockMapping
    security:       Array'u8
}

impl Node
{
    mtd isDirectory()->bool => (.attributes & FileAttributeDirectory) != 0

    mtd blockSearch(logical: u64)->{found: bool, index: u64}
    {
        var low  = 0'u64
        var high = .blocks.count
        while low < high
        {
            let middle = low + (high - low) / 2
            if .blocks[middle].logical < logical do
                low = middle + 1
            else do
                high = middle
        }

        return {low < .blocks.count and .blocks[low].logical == logical, low}
    }

    // Length of the run of contiguous mappings starting at `index`.
    //
    // Block mappings are stored as runs, so a defragmented file costs one
    // record instead of one per block.
    mtd const runLength(index: u64)->u64
    {
        var result = 1'u64
        while index + result < .blocks.count and
              .blocks[index + result].logical == .blocks[index].logical + result and
              .blocks[index + result].physical == .blocks[index].physical + result do
            result += 1
        return result
    }

    // Number of runs the block mappings collapse into.
    mtd const runCount()->u64
    {
        var result = 0'u64
        var index  = 0'u64
        while index < .blocks.count
        {
            result += 1
            index  += .runLength(index)
        }

        return result
    }
}
