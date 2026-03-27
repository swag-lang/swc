#global fileprivate

struct Counter
{
    count: s32
}

impl Counter
{
    mtd const whereFunction(n: s32)->bool => .count == n
}

#test
{
    let counter = Counter{count: 4}
    @assert(counter.whereFunction(4))
    @assert(!counter.whereFunction(3))
}
