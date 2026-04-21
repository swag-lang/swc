#global fileprivate

// An array literal must carry at least one element so its element type can be inferred.
#test
{
    var a = []                   // swc-expected-error {{sema_err_empty_array_literal}}
}

#test
{
    let b = []                   // swc-expected-error {{sema_err_empty_array_literal}}
}
