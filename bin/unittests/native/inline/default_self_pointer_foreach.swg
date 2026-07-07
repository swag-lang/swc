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
    mtd(ptr: bool, back: bool) opVisit(stmt: #code void)
    {
        #if back do
            return

        #if ptr
        {
            #macro
            {
                let #alias0 = cast(*InlineDefaultSelfCell) &(#up me.values[0])
                let #alias1 = 0'u64
                #inject(#up stmt)
            }
        }
        #else
        {
            #macro
            {
                let #alias0 = #up me.values[0]
                let #alias1 = 0'u64
                #inject(#up stmt)
            }
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
