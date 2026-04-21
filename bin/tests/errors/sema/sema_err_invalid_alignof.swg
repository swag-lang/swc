#global fileprivate

namespace NS {}

// '#alignof' cannot be applied to things that are not types or typed expressions (namespaces, attributes, ...).
#test
{
    const a = #alignof(NS)                   // swc-expected-error {{sema_err_invalid_alignof}}
}
