#global public

var copies: s32
var moves: s32

struct FwdValue
{
    public x: s32
}

impl FwdValue
{
    mtd opPostCopy() { copies += 1 }
    mtd opPostMove() { moves += 1 }
    mtd opDrop() {}
}

var slot: FwdValue

func store(value: #fwd FwdValue)
{
    slot = #nodrop #fwd value
}

func copyCount()->s32 => copies
func moveCount()->s32 => moves

#[Swag.NoCopy]
struct MoveOnly
{
    public x: s32
}

impl MoveOnly
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

var moveOnlySlot: MoveOnly

func storeMoveOnly(value: #fwd MoveOnly)
{
    moveOnlySlot = #nodrop #fwd value
}

func moveOnlyValue()->s32 => moveOnlySlot.x
