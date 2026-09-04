#global private

struct DefiniteInitItem
{
    value: s32
}

struct DefiniteInitOwner
{
    required: *DefiniteInitItem
}

impl DefiniteInitOwner
{
    mtd opDrop() {}
}

func definiteInitWholeUse()
{
    var value: *DefiniteInitItem
    discard value     // swc-expected-error {{sema_err_definite_init_use}}
}

func definiteInitFieldUse()
{
    var value: DefiniteInitOwner
    discard value.required     // swc-expected-error {{sema_err_definite_init_field_use}}
}

func definiteInitConditionalDrop(condition: bool, item: *DefiniteInitItem)
{
    var value: DefiniteInitOwner
    if condition do
        value = {required: item}
    value = {required: item}     // swc-expected-error {{sema_err_definite_init_drop}}
}

func definiteInitIndexedWrite(item: *DefiniteInitItem)
{
    var slots: [3] *DefiniteInitItem
    slots[0] = item     // swc-expected-error {{sema_err_definite_init_use}}
}

struct DefiniteInitPart
{
    marker: s32 = 7
    other:  s32
}

struct DefiniteInitMixed
{
    required: *DefiniteInitItem
    part:     DefiniteInitPart
}

func definiteInitNestedWrite(item: *DefiniteInitItem)
{
    var value: DefiniteInitMixed
    value.required   = item
    value.part.other = 1     // swc-expected-error {{sema_err_definite_init_field_use}}
}
