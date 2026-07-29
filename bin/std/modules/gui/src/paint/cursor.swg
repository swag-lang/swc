#global public

// Selects cursor shape.
enum CursorShape
{
    Arrow // Selects arrow.
    SizeWE // Selects size we.
    SizeNS // Selects size ns.
    SizeNWSE // Selects size nwse.
    SizeNESW // Selects size nesw.
    SizeAll // Selects size all.
    Cross // Selects cross.
    Help // Selects help.
    Hand // Selects hand.
    IBeam // Selects i beam.
    No // Selects no.
    Wait // Selects wait.
}

// Represents cursor.
struct Cursor
{
    using native: NativeCursor // Embedded native state.
}

impl Cursor
{
    // Force the wait cursor
    func wait()
    {
        apply(Cursor.from(CursorShape.Wait))
    }

    // Returns true if the cursor is defined
    mtd isValid()->bool
    {
        return .native.cursor != null
    }

    // Destroy the cursor
    mtd destroy()
    {
        .native.cursor = null
    }
}
