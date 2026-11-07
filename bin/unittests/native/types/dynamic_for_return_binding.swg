#global private

#[Swag.DynCast]
struct ForBindingBase {}

struct ForBindingMiddle
{
    using base: ForBindingBase
}

struct ForBindingDerived
{
    using middle: ForBindingMiddle
    value: s32 = 42
}

func findForBinding(items: [..] *ForBindingBase)->*ForBindingDerived?
{
    for child in items
    {
        if child is ForBindingDerived as derived do
            return derived
    }

    return null
}

#test
{
    var derived: ForBindingDerived
    var middle:  ForBindingMiddle
    var items:   [2] *ForBindingBase = [&middle, &derived]
    Swag.require(findForBinding(items) == &derived)

    let unmatched: [1] *ForBindingBase = [&middle]
    Swag.require(findForBinding(unmatched) == null)
}
