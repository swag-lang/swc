#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
