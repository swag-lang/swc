#global fileprivate

var A: #null const bool     // swc-expected-error {{sema_err_bad_type_qualifier}}
var B: const bool           // swc-expected-error {{sema_err_bad_type_qualifier}}
var C: #null bool           // swc-expected-error {{sema_err_bad_type_qualifier}}
