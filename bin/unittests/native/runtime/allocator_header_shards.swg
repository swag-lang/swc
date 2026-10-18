#global private

using Swag

// Header addresses spaced like host reservations must use every shard, even with larger alignments.
#test
{
    var allocator: Allocator
    for stride in [65536'u64, 262144, 1048576, 4194304, 33554432, 1073741824]
    {
        var used: [AllocatorHeaderShardCount] bool
        for i in 64
        {
            let header = cast(*AllocatorHeader, ((i + 1) * stride))
            let shard  = allocator.shardOf(header)
            for j in AllocatorHeaderShardCount where shard == &allocator.shards[j] do
                used[j] = true
        }
        for present in used do
            Swag.assert(present)
    }
}
