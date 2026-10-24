#global private

enum ConstCaseKind
{
    None
    Number
    Pair
}

struct ConstCaseHolder
{
    using value: union(ConstCaseKind)
    {
        case .Number: number: s32 = 7
        case .Pair:   pair:   {a, b: s32}
    } = .Number
}

// A constant union names its case: the kind, a test and a payload read all fold.
const holder = ConstCaseHolder{}
#assert(Swag.kindOf(holder.value) == .Number)
#assert(holder.value is .Number)
#assert(not (holder.value is .Pair))
#assert(holder.number == 7)

// The tag comes first, and every member starts at the payload offset after it.
#assert(#sizeof(ConstCaseHolder) == 12)
#assert(#offsetof(ConstCaseHolder.number) == 4)
#assert(#offsetof(ConstCaseHolder.pair) == 4)
