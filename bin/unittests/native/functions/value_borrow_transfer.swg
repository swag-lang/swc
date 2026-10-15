#global private
#global #[Swag.Safety(.ValueBorrow, true)]

// Reduced from the SVG parser: consuming a value needs a move parameter, not a value borrow.
var copies, drops: u32
struct Owner { value, padding1, padding2: u64 }
impl Owner
{
    mtd opPostCopy() { copies += 1 }
    mtd opDrop() { if .value != 0 do drops += 1 }
}

#[Swag.NoInline]
func consume(value: #move Owner)->u64
{
    let owned = #move value
    return owned.value
}

#[Swag.NoInline]
func borrowedForward(value: Owner)->u64 => consume(#move value)

#[Swag.NoInline]
func ownedForward(value: #move Owner)->u64 => consume(#move value)

#[Swag.Inline]
func inlineOwnedForward(value: #move Owner)->u64 => consume(#move value)

#test
{
    var value: Owner = {value: 353}
    let caught       = Swag.catchPanic(func|&value|() { discard borrowedForward(value) })
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
    Swag.assert(value.value == 353)
}

#test
{
    for inlineCall in [false, true]
    {
        copies, drops = 0
        var value: Owner = {value: 359}
        let result       = inlineCall ? inlineOwnedForward(#move value) : ownedForward(#move value)
        Swag.assert(result == 359 and value.value == 0)
        Swag.assert(copies == 0 and drops == 1)
    }
}
