#global private
#global #[Swag.Propagate]     // swc-expected-error {{sema_err_attribute_usage}}

// '#global' applies an attribute to everything the file declares, so the attribute has to
// accept 'File' explicitly. 'Swag.Propagate' changes how one body reads: it is written on a
// function, or on a block of functions, never on a whole file.
