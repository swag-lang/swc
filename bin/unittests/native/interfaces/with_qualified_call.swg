#global private

// Inside 'with subject', '.IFace.method()' is 'subject.IFace.method()': the leading-dot
// qualifier names the subject's implementation, and the subject is the receiver.

interface IWithQualifiedSetup
{
    mtd setup(owner: *WithQualifiedOwner)
    mtd total()->s32
}

struct WithQualifiedOwner
{
    count: s32
}

struct WithQualifiedThing
{
    owner: *WithQualifiedOwner?
    value: s32
}

impl IWithQualifiedSetup for WithQualifiedThing
{
    mtd impl setup(owner: *WithQualifiedOwner)
    {
        .owner      = owner
        owner.count += 1
    }

    mtd impl total()->s32 => .value + 1
}

func withQualifiedThroughPointer(thing: *WithQualifiedThing, owner: *WithQualifiedOwner)->s32
{
    with thing
    {
        .value = 5
        .IWithQualifiedSetup.setup(owner)
        return .IWithQualifiedSetup.total()
    }
}

#test
{
    var owner: WithQualifiedOwner
    var thing: WithQualifiedThing
    thing.IWithQualifiedSetup.setup(&owner)
    Swag.require(thing.owner == &owner)

    var other: WithQualifiedThing
    with other
    {
        .IWithQualifiedSetup.setup(&owner)
        .value = 2
    }
    Swag.require(other.owner == &owner)
    Swag.require(other.IWithQualifiedSetup.total() == 3)
    Swag.require(owner.count == 2)

    var third: WithQualifiedThing
    Swag.require(withQualifiedThroughPointer(&third, &owner) == 6)
    Swag.require(third.owner == &owner)
    Swag.require(owner.count == 3)
}
