#global private

var A: const bool?     // swc-expected-error {{sema_err_bad_type_qualifier}}
var B: const bool      // swc-expected-error {{sema_err_bad_type_qualifier}}
var C: bool?           // swc-expected-error {{sema_err_bad_type_qualifier}}
