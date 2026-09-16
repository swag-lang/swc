#global private

interface IDynamicField {}
struct DynamicField { value: s32 = 42 }
impl IDynamicField for DynamicField {}

struct NestedDynamicField { inner: DynamicField }
impl IDynamicField for NestedDynamicField {}

func borrowNestedDynamicField(view: IDynamicField)->*s32?
{
    if view is NestedDynamicField as value do
        return &value.inner.value
    return null
}

func borrowDynamicField(view: IDynamicField)->*s32?
{
    switch view
    {
    case DynamicField as value:
        return &value.value
    }
    return null
}

#test
{
    var value: DynamicField
    let field = borrowDynamicField(&value)
    Swag.assert(field == &value.value)
    var nested: NestedDynamicField
    Swag.assert(borrowNestedDynamicField(&nested) == &nested.inner.value)
}
