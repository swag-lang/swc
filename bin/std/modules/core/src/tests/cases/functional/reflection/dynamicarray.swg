#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

var ReflectionDynamicArrayDropCount: u32

struct ReflectionDynamicArrayDropProbe
{
    value: s32
}

impl ReflectionDynamicArrayDropProbe
{
    mtd opDrop()
    {
        ReflectionDynamicArrayDropCount += 1
    }
}

#test
{
    ReflectionDynamicArrayDropCount = 0
    var values: Array'ReflectionDynamicArrayDropProbe

    let first = cast(*ReflectionDynamicArrayDropProbe,
                     Reflection.appendDynamicArrayElement(&values, #typeof(ReflectionDynamicArrayDropProbe)))
    first.value = 10
    let second = cast(*ReflectionDynamicArrayDropProbe,
                      Reflection.appendDynamicArrayElement(&values, #typeof(ReflectionDynamicArrayDropProbe)))
    second.value = 20
    let capacity = values.capacity

    Reflection.clearDynamicArray(&values, #typeof(ReflectionDynamicArrayDropProbe))
    Swag.require(values.count == 0)
    Swag.require(values.capacity == capacity)
    Swag.require(ReflectionDynamicArrayDropCount == 2)

    let reused = cast(*ReflectionDynamicArrayDropProbe,
                      Reflection.appendDynamicArrayElement(&values, #typeof(ReflectionDynamicArrayDropProbe)))
    Swag.require(reused.value == 0)
    Reflection.clearDynamicArray(&values, #typeof(ReflectionDynamicArrayDropProbe))
    Swag.require(ReflectionDynamicArrayDropCount == 3)
}

#test
{
    var values: [3] s32 = [10, 20, 30]
    Reflection.swapRuntimeValues(&values[0], #typeof(s32), 0, 2)
    Swag.require(values == [30, 20, 10])

    Reflection.swapRuntimeValues(&values[0], #typeof(s32), 1, 1)
    Swag.require(values == [30, 20, 10])
}
