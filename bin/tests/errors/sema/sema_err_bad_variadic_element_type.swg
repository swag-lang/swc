#global fileprivate

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

// Typed variadics require a storable element type; void and aliases to void are rejected.
func direct(values: void...) {}                 // swc-expected-error {{sema_err_bad_variadic_element_type}}

func withHead(head: s32, values: void...) {}    // swc-expected-error {{sema_err_bad_variadic_element_type}}

var directFuncType: func(void...) = null        // swc-expected-error {{sema_err_bad_variadic_element_type}}

func aliasParam(values: VoidAlias...) {}        // swc-expected-error {{sema_err_bad_variadic_element_type}}

var aliasFuncType: func(VoidAlias...) = null    // swc-expected-error {{sema_err_bad_variadic_element_type}}

func strictAlias(values: StrictVoidAlias...) {} // swc-expected-error {{sema_err_bad_variadic_element_type}}

var strictAliasFuncType: func(StrictVoidAlias...) = null // swc-expected-error {{sema_err_bad_variadic_element_type}}
