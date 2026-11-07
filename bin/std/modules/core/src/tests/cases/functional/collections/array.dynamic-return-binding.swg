#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.DynCast]
struct ArrayBindingBase {}

struct ArrayBindingMiddle
{
    using base: ArrayBindingBase
}

struct ArrayBindingDerived
{
    using middle: ArrayBindingMiddle
    value: s32 = 42
}

func findArrayBinding(items: *Array'(*ArrayBindingBase))->*ArrayBindingDerived?
{
    for child in items[]
    {
        if child is ArrayBindingDerived as derived do
            return derived
    }

    return null
}

#test
{
    var middle:  ArrayBindingMiddle
    var derived: ArrayBindingDerived
    var items:   Array'(*ArrayBindingBase)
    items.add(&middle)
    items.add(&derived)
    Swag.require(findArrayBinding(&items) == &derived)

    items.removeBack()
    Swag.require(findArrayBinding(&items) == null)
}
