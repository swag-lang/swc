#global private

// A 'Swag.Late' slot starts as null storage and receives its value later, but its type stays
// non-null. A condition on it therefore does not ask whether it was set: 'Swag.isSet' does.

struct BoolTestLateLabel
{
    width: s32
}

struct BoolTestLateItem
{
    #[Swag.Late]
    label: *BoolTestLateLabel
}

#[Swag.Late]
var g_boolTestLateSlot: *BoolTestLateLabel

func boolTestLateField(item: *BoolTestLateItem)->s32
{
    if item.label do     // swc-expected-error {{sema_err_bool_test_late_slot}}
        return item.label.width
    return 0
}

func boolTestLateGlobal()->s32
{
    if g_boolTestLateSlot do     // swc-expected-error {{sema_err_bool_test_late_slot}}
        return g_boolTestLateSlot.width
    return 0
}

// The spelling that asks the question.
func boolTestLateIsSet(item: *BoolTestLateItem)->s32
{
    if Swag.isSet(item.label) do
        return item.label.width
    return 0
}
