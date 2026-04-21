#global fileprivate

const InvalidWrapFloat = 127.0 + #wrap 1            // swc-expected-error {{sema_err_modifier_only_integer}}
const InvalidPromFloat = 127.0 + #prom 1            // swc-expected-error {{sema_err_modifier_only_integer}}
const InvalidPromWrapFloat = 127.0 + #prom #wrap 1  // swc-expected-error {{sema_err_modifier_only_integer}}
