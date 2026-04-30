#global fileprivate

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

// Arrays require a storable element type; void and aliases to void are rejected.
var directArray: [1] void                 // swc-expected-error {{sema_err_bad_array_element_type}}

func badParam(p: [1] void) {}             // swc-expected-error {{sema_err_bad_array_element_type}}

var inferredArray: [?] void               // swc-expected-error {{sema_err_bad_array_element_type}}

var aliasArray: [1] VoidAlias             // swc-expected-error {{sema_err_bad_array_element_type}}

func badAlias(p: [?] VoidAlias) {}        // swc-expected-error {{sema_err_bad_array_element_type}}

var strictAliasArray: [1] StrictVoidAlias // swc-expected-error {{sema_err_bad_array_element_type}}

func badStrictAlias(p: [?] StrictVoidAlias) {} // swc-expected-error {{sema_err_bad_array_element_type}}
