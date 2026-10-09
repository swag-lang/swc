#global private

// 'Swag.Propagate' sends unmarked failures through the function's own 'fail' exit, so a
// function that cannot fail has nowhere to send them.

#[Swag.Propagate]
func propagateWithoutFail() {}     // swc-expected-error {{sema_err_propagate_needs_fail}}
