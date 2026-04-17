#global fileprivate

#test { const A = #hastag(0) } // swc-expected-error {{sema_err_invalid_type}}
#test { const B = #gettag(0, string, "fallback") } // swc-expected-error {{sema_err_invalid_type}}
