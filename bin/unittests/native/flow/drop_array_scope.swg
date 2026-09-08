#global private

var dropped: u32
var sum:     u32

#[Swag.NoCopy]
struct Item
{
    value = 7'u32
}

impl Item
{
    mtd opDrop() { dropped += 1; sum += .value }
}

#test
{
    dropped = 0
    sum     = 0
    {
        var items: [3] Item
        for &item in items do
            item.value = 1
    }
    Swag.assert(dropped == 3)
    Swag.assert(sum == 3)
}

alias Grid = [2][3] Item

func leaveArrayScope(early: bool)
{
    var items: Grid
    if early do
        return
    items[1][2].value = 9
}

#test
{
    dropped = 0
    sum     = 0
    leaveArrayScope(true)
    Swag.assert(dropped == 6 and sum == 42)
    leaveArrayScope(false)
    Swag.assert(dropped == 12 and sum == 86)
}

struct ArrayFailure {}

func failArrayScope() fail
{
    var items: [4] Item
    fail ArrayFailure{}
}

#test
{
    dropped = 0
    sum     = 0
    catch failArrayScope() as error
    Swag.assert(error != null and error is ArrayFailure)
    Swag.assert(dropped == 4 and sum == 28)
}
