#global private

func impossibleNullableParameter(value: #null *s32)->s32     // swc-expected-error {{sema_err_nullable_param_contract}}
{
    return dref value
}
