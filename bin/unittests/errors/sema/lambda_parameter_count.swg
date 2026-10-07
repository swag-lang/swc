#global private

struct CallbackOwner { callback: (func||()->bool)? }

#test
{
    var owner: CallbackOwner
    // swc-expected-error@(+1) {{sema_err_lambda_parameter_count}}
    owner.callback = func(value)->bool => value != 0
}
