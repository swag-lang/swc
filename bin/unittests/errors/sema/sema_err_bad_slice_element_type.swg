#global fileprivate

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

// Slices require a storable element type; void and other non-storable types are rejected.
var a: [..] void                 // swc-expected-error {{sema_err_bad_slice_element_type}}

func bad(p: [..] void) {}        // swc-expected-error {{sema_err_bad_slice_element_type}}

var aliasSlice: [..] VoidAlias   // swc-expected-error {{sema_err_bad_slice_element_type}}

func badAlias(p: [..] VoidAlias) {} // swc-expected-error {{sema_err_bad_slice_element_type}}

var strictAliasSlice: [..] StrictVoidAlias // swc-expected-error {{sema_err_bad_slice_element_type}}

func badStrictAlias(p: [..] StrictVoidAlias) {} // swc-expected-error {{sema_err_bad_slice_element_type}}
