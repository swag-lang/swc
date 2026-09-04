#global private

// A 'late' slot starts as null storage and receives its value later, but its type stays
// non-null. A condition on it therefore does not ask whether it was set: compare it with null.

struct BoolTestLateLabel
{
    width: s32
}

struct BoolTestLateItem
{
    late label: *BoolTestLateLabel
}

late var g_boolTestLateSlot: *BoolTestLateLabel

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

// A null comparison asks the question without reading the field.
func boolTestLatePresence(item: *BoolTestLateItem)->s32
{
    if (item.label != null) do
        return item.label.width
    return 0
}
