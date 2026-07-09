#global private

struct InlineDefaultSelfCell
{
    value: s32
}

struct InlineDefaultSelfCells
{
    values: [1] InlineDefaultSelfCell
}

impl InlineDefaultSelfCells
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) opVisit(stmt: #code(item, index: u64))
    {
        #if back do
            return

        #if ptr
        {
            #inject(stmt, item = cast(*InlineDefaultSelfCell) &(me.values[0]), index = 0'u64)
        }
        #else
        {
            #inject(stmt, item = me.values[0], index = 0'u64)
        }
    }
}

var InlineDefaultSelfItems: InlineDefaultSelfCells

#[Swag.Inline]
func inlineDefaultSelfPtr(x, y: s32, self: *InlineDefaultSelfCell = null)->bool
{
    foreach &c in InlineDefaultSelfItems
    {
        if c == self do
            return false
        if c.value == x + y do
            return true
    }

    return false
}

#test
{
    @assert(inlineDefaultSelfPtr(0, 0))
}
