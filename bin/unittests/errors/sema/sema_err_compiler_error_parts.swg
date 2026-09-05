#global private

const Suffix = "ms"
#error("unknown suffix '", Suffix, "' at line ", #line)     // swc-expected-error {{sema_err_compiler_error}}
