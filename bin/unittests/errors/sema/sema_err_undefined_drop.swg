#global private

struct DroppableValue
{
    value: s32
}

impl DroppableValue
{
    mtd opDrop() {}
}

func makeDroppable(value: s32)->DroppableValue
{
    return DroppableValue{value: value}
}

func maybeReassignUndefined(condition: bool)
{
    var value: DroppableValue = undefined
    if condition do
        value = makeDroppable(1)
    value     = makeDroppable(2)     // swc-expected-error {{sema_err_undefined_drop}}
}
