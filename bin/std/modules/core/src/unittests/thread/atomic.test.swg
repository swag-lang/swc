#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    var value: s8 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s16 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s32 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s64 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u8 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u16 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u32 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u64 = 1
    @assert(Atomic.add(&value, 2) == 1)
    @assert(value == 3)
    @assert(Atomic.logicAnd(&value, 1) == 3)
    @assert(value == 1)
    @assert(Atomic.logicOr(&value, 4) == 1)
    @assert(value == 5)
    @assert(Atomic.logicXor(&value, 6) == 5)
    @assert(value == 3)
    @assert(Atomic.exchange(&value, 7) == 3)
    @assert(value == 7)
    @assert(Atomic.compareExchange(&value, 7, 9) == 7)
    @assert(value == 9)
    @assert(Atomic.compareExchange(&value, 7, 1) == 9)
    @assert(value == 9)
    @assert(Atomic.get(&value) == 9)
}
