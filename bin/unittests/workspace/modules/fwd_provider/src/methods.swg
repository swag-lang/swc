#global public

struct FwdStore
{
    public slot: FwdValue
}

impl FwdStore
{
    mtd put(value: #fwd FwdValue)
    {
        .slot = #nodrop #fwd value
    }

    mtd const value()->s32 => .slot.x
}
