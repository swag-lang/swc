#global namespace InlineSw

// Provider for inline_crossast_switch_test.swg (separate file => separate Ast).
// classify() is a non-generic #[Inline] method with a switch whose case labels reference enum
// values UNQUALIFIED within this namespace (resolved against the switched value's enum type).
// When inlined at a call site outside InlineSw, the case-type/value resolution must be preserved.

enum SwKind
{
    A
    B
    C
}

struct SwClassifier
{
    bias: s32
}

impl SwClassifier
{
    #[Swag.Inline]
    mtd classify(k: SwKind)->s32
    {
        switch k
        {
        case A:
            return .bias + 10
        case B:
            return .bias + 20
        default:
            return .bias + 30
        }
    }
}
