#global fileprivate

// Slices require a storable element type; void and other non-storable types are rejected.
var a: [..] void                 // swc-expected-error {{sema_err_bad_slice_element_type}}

func bad(p: [..] void) {}        // swc-expected-error {{sema_err_bad_slice_element_type}}
