#global if #command == Swag.CompilerCommand.Test
#global private

using Core

var objectDrops: u32

struct AllocatedObject
{
    value = 37'u64
}

impl AllocatedObject
{
    mtd opDrop() { objectDrops += 1 }
}

// The runtime-type overloads keep their private lifecycle helpers inside core.
#test
{
    objectDrops = 0
    let type: typeinfo = AllocatedObject
    let storage        = Memory.new(type)!
    Swag.assert((cast(*AllocatedObject) storage).value == 37)
    Memory.delete(storage, type)
    Swag.assert(objectDrops == 1)
}

// Generic construction imports the allocation body and runs the consumer's hooks.
#test
{
    objectDrops = 0
    let object = Memory.new'AllocatedObject()
    Swag.assert(object.value == 37)
    Memory.delete(object)
    Swag.assert(objectDrops == 1)

    let objects = Memory.new'AllocatedObject(3)
    for i in 3 do Swag.assert(objects[i].value == 37)
    Memory.delete(objects, 3)
    Swag.assert(objectDrops == 4)
}
