#global private

alias VoidAlias = void

#[Swag.Strict]
alias StrictVoidAlias = void

// Variables, fields, and parameters require a storable type; void and aliases to void are rejected.
var globalDirect: void                 // swc-expected-error {{sema_err_bad_storage_type}}
var globalAlias: VoidAlias             // swc-expected-error {{sema_err_bad_storage_type}}
var globalStrictAlias: StrictVoidAlias // swc-expected-error {{sema_err_bad_storage_type}}

struct BadFieldDirect
{
    direct: void                       // swc-expected-error {{sema_err_bad_storage_type}}
}

struct BadFieldAlias
{
    aliasField: VoidAlias              // swc-expected-error {{sema_err_bad_storage_type}}
}

struct BadFieldStrictAlias
{
    strictAliasField: StrictVoidAlias  // swc-expected-error {{sema_err_bad_storage_type}}
}

func directParam(value: void) {}       // swc-expected-error {{sema_err_bad_storage_type}}
func aliasParam(value: VoidAlias) {}   // swc-expected-error {{sema_err_bad_storage_type}}
func strictAliasParam(value: StrictVoidAlias) {} // swc-expected-error {{sema_err_bad_storage_type}}

#test
{
    var localDirect: void              // swc-expected-error {{sema_err_bad_storage_type}}
}

#test
{
    var localAlias: VoidAlias          // swc-expected-error {{sema_err_bad_storage_type}}
}

#test
{
    var localStrictAlias: StrictVoidAlias // swc-expected-error {{sema_err_bad_storage_type}}
}
