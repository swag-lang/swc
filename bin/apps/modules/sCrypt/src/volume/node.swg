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
}
