#global private

struct MemberPointerOperation
{
    started: bool
}

struct MemberPointerPreview
{
    using operation: MemberPointerOperation
}

func readThroughPointerSlot(slot: **MemberPointerPreview)
{
    let started = slot.started     // swc-expected-error {{sema_err_member_needs_deref}}
}

#test
{
    var preview = MemberPointerPreview{operation: {started: true}}
    var previews: [1] *MemberPointerPreview = [&preview]
    for &entry in previews
    {
        let started = entry.started     // swc-expected-error {{sema_err_member_needs_deref}}
    }
}
