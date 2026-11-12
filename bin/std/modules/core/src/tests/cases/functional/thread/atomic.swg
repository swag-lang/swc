#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct AtomicCounterShared
{
    ready:       u32
    start:       u32
    done:        u32
    value:       u64
    previousSum: u64
}

func incrementAtomicCounter(thread: const *Threading.Thread)
{
    let shared = cast(*AtomicCounterShared, unwrap thread.userParam)
    discard Atomic.add(&shared.ready, 1)
    while Atomic.get(&shared.start) == 0 do
        Threading.Thread.yield()

    var previousSum = 0'u64
    for 10000
    {
        previousSum += Atomic.add(&shared.value, 1)
    }

    discard Atomic.add(&shared.previousSum, previousSum)
    discard Atomic.add(&shared.done, 1)
}

#test
{
    const WorkerCount    = 4'u64
    const IterationCount = 10000'u64
    var shared:  AtomicCounterShared
    var threads: [WorkerCount] Threading.Thread

    for &thread in threads
    {
        discard expect thread.init(&incrementAtomicCounter, &shared)
        discard expect thread.start()
    }

    while Atomic.get(&shared.ready) != WorkerCount do
        Threading.Thread.yield()
    discard Atomic.exchange(&shared.start, 1)

    for &thread in threads do
        thread.wait()

    let expectedCount = WorkerCount * IterationCount
    Swag.require(Atomic.get(&shared.value) == expectedCount)
    Swag.require(Atomic.get(&shared.previousSum) == expectedCount * (expectedCount - 1) / 2)
    Swag.require(Atomic.get(&shared.done) == WorkerCount)
}

#test
{
    var value: s8 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: s16 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: s32 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: s64 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: u8 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: u16 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: u32 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}

#test
{
    var value: u64 = 1
    Swag.require(Atomic.add(&value, 2) == 1)
    Swag.require(value == 3)
    Swag.require(Atomic.logicAnd(&value, 1) == 3)
    Swag.require(value == 1)
    Swag.require(Atomic.logicOr(&value, 4) == 1)
    Swag.require(value == 5)
    Swag.require(Atomic.logicXor(&value, 6) == 5)
    Swag.require(value == 3)
    Swag.require(Atomic.exchange(&value, 7) == 3)
    Swag.require(value == 7)
    Swag.require(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.require(value == 9)
    Swag.require(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.require(value == 9)
    Swag.require(Atomic.get(&value) == 9)
}
