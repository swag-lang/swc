#global private

func expectedValue(index, rounds: u64)->u64
{
    var value = index + 1
    for round in rounds
    {
        value ^= value << 13
        value ^= value >> 7
        value ^= value << 17
    }
    return value
}

func fillBalanced(values: [..] u64, visits: [..] Swag.AtomicValue'u32, begin, heavyBegin, heavyEnd: u64)
{
    parallel for |values, visits, begin, heavyBegin, heavyEnd| index in begin until begin + values.count
    {
        let offset = index - begin
        let rounds = offset >= heavyBegin and offset < heavyEnd ? 4096'u64 : 128'u64
        values[offset] = expectedValue(offset, rounds)
        visits[offset].add(1)
    }
}

// Odd bounds leave a short final block; a cursor reaching U64.Max must stop without wrapping.
// Reuse the body with the expensive region at either end and with different borrowed arrays.
#test
{
    Swag.setWorkerCount(4)
    for pass in 3
    {
        var values: [2053] u64
        var visits: [2053] Swag.AtomicValue'u32
        let heavyBegin = pass == 0 ? 0'u64 : 1796'u64
        let heavyEnd   = heavyBegin + 257
        let begin      = pass == 2 ? Swag.U64.Max - values.count : 19'u64
        fillBalanced(values, visits, begin, heavyBegin, heavyEnd)
        for index in values.count
        {
            let rounds = index >= heavyBegin and index < heavyEnd ? 4096'u64 : 128'u64
            Swag.assert(visits[index].load() == 1)
            Swag.assert(values[index] == expectedValue(index, rounds))
        }
    }
}

struct BalanceFailure { index: u64 }

// A failed block can leave partial effects. All published effects and cleanup must finish
// before the caller catches the error, and no block may visit an index twice.
#test
{
    var visits:  [2053] Swag.AtomicValue'u32
    var entered: Swag.AtomicValue'u32
    var left:    Swag.AtomicValue'u32
    catch parallel for |&visits, &entered, &left| index in visits.count
    {
        entered.add(1)
        defer left.add(1)
        visits[index].add(1)
        let value = expectedValue(index, 4096)
        if index == 1796 do
            fail BalanceFailure{value}
    } as error
    Swag.assert(error != null and error is BalanceFailure)
    Swag.assert((cast(const *BalanceFailure) error).index == expectedValue(1796, 4096))
    Swag.assert(entered.load() == left.load())
    Swag.assert(visits[1796].load() == 1)
    for visit in visits do
        Swag.assert(visit.load() <= 1)
}
