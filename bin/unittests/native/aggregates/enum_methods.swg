#global private

// Enum with impl: associated functions and enum patterns.

enum Direction
{
    North
    East
    South
    West
}

impl Direction
{
    func opposite(val: Direction)->Direction
    {
        using Direction
        switch val
        {
        case .North: return South
        case .South: return North
        case .East:  return West
        case .West:  return East
        }
    }

    func isVertical(val: Direction)->bool
    {
        using Direction
        return val == North or val == South
    }

    func isHorizontal(val: Direction)->bool
    {
        using Direction
        return val == East or val == West
    }
}

// Qualified call.
#test
{
    let d = Direction.North
    Swag.assert(Direction.opposite(d) == Direction.South)
    Swag.assert(Direction.isVertical(d))
    Swag.assert(!Direction.isHorizontal(d))
}

#test
{
    let d = Direction.East
    Swag.assert(Direction.opposite(d) == Direction.West)
    Swag.assert(!Direction.isVertical(d))
    Swag.assert(Direction.isHorizontal(d))
}

// Using directive.
#test
{
    using Direction
    Swag.assert(opposite(South) == North)
    Swag.assert(opposite(West) == East)
    Swag.assert(isVertical(North))
    Swag.assert(!isVertical(East))
}

// Round-trip.
#test
{
    using Direction
    Swag.assert(opposite(opposite(North)) == North)
    Swag.assert(opposite(opposite(East)) == East)
}

// Enum with explicit values.
enum Priority
{
    Low    = 1
    Medium = 5
    High   = 10
}

impl Priority
{
    func isUrgent(val: Priority)->bool => val == Priority.High
    func isLow(val: Priority)->bool    => val == Priority.Low
}

#test
{
    Swag.assert(!Priority.isUrgent(Priority.Medium))
    Swag.assert(Priority.isUrgent(Priority.High))
    Swag.assert(Priority.isLow(Priority.Low))
    Swag.assert(!Priority.isLow(Priority.High))
    let p = Priority.Low
    Swag.assert(p.isLow() == true)
}

// Enum flags with bitwise operations.
#[Swag.EnumFlags]
enum Permissions: u32
{
    Read
    Write
    Execute
}

#test
{
    let rw = Permissions.Read | Permissions.Write
    Swag.assert((cast(u32) rw & cast(u32) Permissions.Read) != 0)
    Swag.assert((cast(u32) rw & cast(u32) Permissions.Write) != 0)
    Swag.assert((cast(u32) rw & cast(u32) Permissions.Execute) == 0)
}

#test
{
    let all = Permissions.Read | Permissions.Write | Permissions.Execute
    Swag.assert(cast(u32) all == 7)
    let toggled = all ^ Permissions.Write
    Swag.assert((cast(u32) toggled & cast(u32) Permissions.Read) != 0)
    Swag.assert((cast(u32) toggled & cast(u32) Permissions.Write) == 0)
    Swag.assert((cast(u32) toggled & cast(u32) Permissions.Execute) != 0)
}

// Enum used as array index.
enum Slot: u8 { A, B, C }

#test
{
    var values: [3] s32 = [10, 20, 30]
    Swag.assert(values[cast(u8) Slot.A] == 10)
    Swag.assert(values[cast(u8) Slot.B] == 20)
    Swag.assert(values[cast(u8) Slot.C] == 30)
}

enum ImportedAliasErrors { FailedToLoad, FailedToSave }

alias ImportedAliasErrorsAlias       = ImportedAliasErrors

#[Swag.Strict]
alias StrictImportedAliasErrorsAlias = ImportedAliasErrors

#test
{
    let loaded = ImportedAliasErrorsAlias.FailedToLoad
    let saved  = StrictImportedAliasErrorsAlias.FailedToSave
    #assert(#typeof(loaded) == ImportedAliasErrors)
    #assert(#typeof(saved) == ImportedAliasErrors)
    Swag.assert(loaded == ImportedAliasErrors.FailedToLoad)
    Swag.assert(saved == ImportedAliasErrors.FailedToSave)
}
