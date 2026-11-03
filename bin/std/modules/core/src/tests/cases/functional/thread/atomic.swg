#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var value: s8 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s16 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s32 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: s64 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u8 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u16 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u32 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}

#test
{
    var value: u64 = 1
    Swag.assert(Atomic.add(&value, 2) == 1)
    Swag.assert(value == 3)
    Swag.assert(Atomic.logicAnd(&value, 1) == 3)
    Swag.assert(value == 1)
    Swag.assert(Atomic.logicOr(&value, 4) == 1)
    Swag.assert(value == 5)
    Swag.assert(Atomic.logicXor(&value, 6) == 5)
    Swag.assert(value == 3)
    Swag.assert(Atomic.exchange(&value, 7) == 3)
    Swag.assert(value == 7)
    Swag.assert(Atomic.compareExchange(&value, 7, 9) == 7)
    Swag.assert(value == 9)
    Swag.assert(Atomic.compareExchange(&value, 7, 1) == 9)
    Swag.assert(value == 9)
    Swag.assert(Atomic.get(&value) == 9)
}
