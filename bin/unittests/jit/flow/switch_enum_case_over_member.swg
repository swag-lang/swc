#global private

enum SwitchSortOrder
{
    Recent
    Name
}

// A receiver whose constants share their names with the values of the enum it switches on.
struct SwitchSortCommands {}

impl SwitchSortCommands
{
    const Recent = "recent"
    const Name   = "name"

    mtd rank(order: SwitchSortOrder)->s32
    {
        switch order
        {
        case .Recent: return 1
        case .Name:   return 2
        }

        return 0
    }

    // The label of an enum switch nested in a switch on the receiver's own constants.
    mtd nested(id: string, order: SwitchSortOrder)->s32
    {
        switch id
        {
        case Recent:
            switch order
            {
            case .Recent: return 1
            default:      return 0
            }
        }

        return 2
    }
}

// The position of a case label requires the enum, so `.Member` names its value before a member
// of the receiver that shares the name.
#test
{
    var commands: SwitchSortCommands
    Swag.assert(commands.rank(.Recent) == 1)
    Swag.assert(commands.rank(.Name) == 2)
    Swag.assert(commands.nested("recent", .Recent) == 1)
    Swag.assert(commands.nested("recent", .Name) == 0)
    Swag.assert(commands.nested("other", .Recent) == 2)
}
