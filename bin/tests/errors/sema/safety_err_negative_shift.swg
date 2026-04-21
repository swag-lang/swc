#global fileprivate

#assert(1 << -1)    // swc-expected-error {{safety_err_negative_shift}}
#assert(1 >> -1)    // swc-expected-error {{safety_err_negative_shift}}
