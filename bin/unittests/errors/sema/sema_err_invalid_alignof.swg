#global private

namespace NS {}

struct(T) GenericAlignofProbe
{
    value: T
}

// '#alignof' cannot be applied to things that are not types or typed expressions (namespaces, attributes, ...).
#assert(#alignof(NS) == 0) // swc-expected-error {{sema_err_invalid_alignof}}
#assert(#alignof(GenericAlignofProbe) == 0) // swc-expected-error {{sema_err_invalid_alignof}}
