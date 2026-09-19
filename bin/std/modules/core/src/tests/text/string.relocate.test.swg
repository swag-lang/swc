#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A slot left behind by a '#relocate' shift is uninitialized, and lifecycle safety poisons it.
// Writing a String into it with '#nodrop #move' must move the bits, never go through the
// String 'opSet' overloads, which read the existing value of the target.
struct(T) Vec
{
    buffer:   [*] T?
    count:    u64
    capacity: u64
}

impl Vec
{
    mtd push(value: #fwd T)
    {
        if not .buffer
        {
            .buffer   = cast([*] T) Memory.alloc(8 * #sizeof(T))
            .capacity = 8
        }

        Swag.init(.buffer! + .count, 1)
        .buffer![.count] = #nodrop #fwd value
        .count += 1
    }

    mtd insertMoved(index: u64, value: #fwd T)
    {
        var staged: T = #fwd value
        .count += 1
        let buffer = .buffer!
        for var idx = .count - 1; idx > index; idx -= 1 do
            buffer[idx] = #relocate buffer[idx - 1]
        buffer[index] = #nodrop #move staged
    }
}

#test
{
    var v: Vec'String
    v.push("one")
    v.push("two")
    v.insertMoved(0, "x")
    let b = v.buffer!
    Swag.assert(b[0] == "x" and b[1] == "one" and b[2] == "two")
}
