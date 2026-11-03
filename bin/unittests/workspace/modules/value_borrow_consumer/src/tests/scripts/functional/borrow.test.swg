#global if #command == Swag.CompilerCommand.Test
#global #[Swag.Safety(.ValueBorrow, true)]
#global private
using BorrowLibrary

func mustReject(action: func||())
{
    let caught = Swag.catchPanic(action)
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
}
#[Swag.NoInline]
func localWrite(target: *Value) { target.first = 0 }
#[Swag.NoInline]
func localRead(value: Value, target: *Value)->u64
{
    BorrowLibrary.write(target)
    return value.first
}

// The write and its active borrow may be emitted by different artifacts in either direction.
#test
{
    var value: Value = {first: 263}
    mustReject(func|&value|() { discard localRead(value, &value) })
    Swag.assert(value.first == 263)
    let observed = localRead(#copy value, &value)
    Swag.assert(observed == 263 and value.first == 0)
}
#test
{
    var value: Value = {first: 269}
    mustReject(func|&value|() { discard readAfterCallback(value, &localWrite, &value) })
    Swag.assert(value.first == 269)
    let observed = readAfterCallback(#copy value, &localWrite, &value)
    Swag.assert(observed == 269 and value.first == 0)
}
#test
{
    var value: Value = {first: 271}
    var other: Value = {first: 277}
    let observed     = readAfterCallback(value, &localWrite, &other)
    Swag.assert(observed == 271 and value.first == 271 and other.first == 0)
    BorrowLibrary.write(&value)
    Swag.assert(read(value) == 0)
}

// Only the DLL registers this borrow; the unchecked forwarding frame adds no record.
#[Swag.NoInline, Swag.Safety(.ValueBorrow, false)]
func fromUncheckedCaller(value: Value, target: *Value)->u64 => readAfterCallback(value, &localWrite, target)

#test
{
    var value: Value = {first: 281}
    mustReject(func|&value|() { discard fromUncheckedCaller(value, &value) })
    Swag.assert(value.first == 281)
}
