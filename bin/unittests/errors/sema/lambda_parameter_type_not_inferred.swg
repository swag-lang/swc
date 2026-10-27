#global private

#test
{
    // swc-expected-error@(+1) {{sema_err_lambda_parameter_type_not_inferred}}
    let callback = func(value) => value
}
