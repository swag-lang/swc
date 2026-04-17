#global fileprivate

#test { const A = #gettag("User.Flag", true, false) } // swc-expected-error {{sema_err_not_type}}
