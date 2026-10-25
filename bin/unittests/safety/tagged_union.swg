#global private

enum SafetyCaseKind
{
    None
    Number
    Text
}

struct SafetyCaseHolder
{
    using value: union(SafetyCaseKind)
    {
        case .Number: number: s32
        case .Text:   text:   string
    } = .None
}

// =============================================
// '!' asserts the case of a payload access: another active case panics under the Switch guard.
// =============================================

#test
{
    #[Swag.Safety(.Switch, true)]
    func readNumber(holdsNumber: bool)->s32
    {
        var holder: SafetyCaseHolder
        if holdsNumber do
            holder.value = .Number{3}
        else do
            holder.value = .Text{"three"}
        return unwrap holder.number     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run readNumber(false)
}

// =============================================
// The matching case passes through the check
// =============================================

#test
{
    #[Swag.Safety(.Switch, true)]
    func readNumber(holdsNumber: bool)->s32
    {
        var holder: SafetyCaseHolder
        if holdsNumber do
            holder.value = .Number{3}
        else do
            holder.value = .Text{"three"}
        return unwrap holder.number
    }

    #assert(#run readNumber(true) == 3)
}
