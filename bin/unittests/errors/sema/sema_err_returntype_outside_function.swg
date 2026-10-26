#global private

// '#returntype' is only legal inside a function body.
var a: #returntype       // swc-expected-error {{sema_err_returntype_outside_function}}
const b: #returntype     // swc-expected-error {{sema_err_returntype_outside_function}}
