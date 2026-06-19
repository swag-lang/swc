#global fileprivate

func badNormal()
{
    #macro // swc-expected-error {{sema_err_macro_requires_macro_fn}}
    {
        let value = 1
    }
}

#[Swag.Mixin]
func badMixin()
{
    #macro // swc-expected-error {{sema_err_macro_requires_macro_fn}}
    {
        let value = 1
    }
}

const TriggerBadMixin = #run
{
    badMixin()
    return 0
}
