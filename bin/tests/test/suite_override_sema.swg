// swc-option suite-sema

#global fileprivate

var Bad: [..] void // swc-expected-error {{sema_err_bad_slice_element_type}}
