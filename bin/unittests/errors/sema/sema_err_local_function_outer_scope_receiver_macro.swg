#global private

struct LocalMethodMacroBox
{
    base: s32
}

#[Swag.Macro]
func bounceOuterReceiver(value: s32)->s32
{
    #macro
    {
        return #up value + 1
    }
}

impl LocalMethodMacroBox
{
    #[Swag.Macro]
    mtd localNestedUpOuterReceiver(delta: s32)->s32
    {
        func pick(buffer: s32)->s32
        {
            return bounceOuterReceiver(#up me.base + #up delta + buffer)
        }

        return pick(1000)
    }
}

const TriggerLocalNestedUpOuterReceiver = #run
{
    var box: LocalMethodMacroBox
    box.base = 40
    return box.localNestedUpOuterReceiver(1) // swc-expected-error {{sema_err_local_function_outer_scope_variable}}
}
