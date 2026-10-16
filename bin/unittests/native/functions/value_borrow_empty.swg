#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct Value { value, padding: u64 }

#[Swag.NoInline]
func writeScalar(target: *u64, value: u64) { target[] = value }

#[Swag.NoInline]
func writeDuringBorrow(value: Value, target: *u64)->u64
{
    writeScalar(target, 99)
    return value.value
}

// Pointer stores must work before and after a borrow, and reject an overlap while it lives.
#test
{
    var value: Value
    writeScalar(&value.value, 31)
    Swag.assert(value.value == 31)
    for 2
    {
        let caught = Swag.catchPanic(func|&value|() { discard writeDuringBorrow(value, &value.value) })
        Swag.assert(caught.raised)
        Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
        Swag.assert(value.value == 31)
        writeScalar(&value.value, 47)
        Swag.assert(value.value == 47)
        writeScalar(&value.value, 31)
    }
}
