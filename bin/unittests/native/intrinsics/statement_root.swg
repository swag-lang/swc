#global private

// An '@' intrinsic that yields a value is a primary expression, so it opens a statement the
// same way an identifier does: the postfix chain that follows it can be an assignment target.

var Sink: u32 = 0

#test
{
    var storage: [16] u8
    storage.buffer[as u32] = 0x0102_0304
    Swag.assert(storage[0] == 4)
    Swag.assert(storage[3] == 1)
}

#test
{
    var storage: [4] u8
    storage.buffer[1] = 0xFF
    Swag.assert(storage[1] == 0xFF)
}

#test
{
    var storage: [4] u32 = [1, 2, 3, 4]
    storage.buffer[2] += 10
    Swag.assert(storage[2] == 13)
}

#test
{
    // The parenthesized and the bound-to-a-local spellings keep working.
    var storage: [4] u8
    (storage.buffer)[as u32] = 0x0102_0304
    let p = storage.buffer
    p[0] = 9
    Swag.assert(storage[0] == 9)
    Swag.assert(storage[3] == 1)
}

#test
{
    // A statement-rooted intrinsic value that nothing assigns to still type-checks as an
    // expression statement.
    var storage: [4] u8
    Sink = storage.count
    Swag.assert(Sink == 4)
}
