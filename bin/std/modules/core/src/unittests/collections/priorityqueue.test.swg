#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct PriorityItem
{
    priority: s32
    id:       s32
}

var g_PriorityItemDrops: s32

impl PriorityItem
{
    mtd opDrop()
    {
        if .id do
            g_PriorityItemDrops += 1
    }
}

#test
{
    var queue: PriorityQueue's32
    queue.initialize(func(left, right: const *s32)->s32 => left[] <=> right[])
    queue.push(5)
    queue.push(1)
    queue.push(3)
    queue.push(1)

    @assert(queue.peek() == 1)
    @assert(queue.pop() == 1)
    @assert(queue.pop() == 1)
    @assert(queue.pop() == 3)
    @assert(queue.pop() == 5)
    @assert(queue.isEmpty())
}

#test
{
    var queue: PriorityQueue's32
    queue.initialize(func(left, right: const *s32)->s32 => right[] <=> left[])
    queue.reserve(8)
    queue.push(2)
    queue.push(9)
    queue.push(4)

    @assert(queue.capacity() >= 8)
    @assert(queue.pop() == 9)
    @assert(queue.pop() == 4)
    @assert(queue.pop() == 2)
}

#test
{
    g_PriorityItemDrops = 0
    {
        var queue: PriorityQueue'PriorityItem
        queue.initialize(func(left, right: const *PriorityItem)->s32 => left.priority <=> right.priority)
        var later  = PriorityItem{priority: 4, id: 4}
        var first  = PriorityItem{priority: 1, id: 1}
        var second = PriorityItem{priority: 2, id: 2}
        queue.push(#move later)
        queue.push(#move first)
        queue.push(#move second)

        let poppedFirst = queue.pop()
        @assert(poppedFirst.id == 1)
        let poppedSecond = queue.pop()
        @assert(poppedSecond.id == 2)
    }

    @assert(g_PriorityItemDrops == 3)
}
