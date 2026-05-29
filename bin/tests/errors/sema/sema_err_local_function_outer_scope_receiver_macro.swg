#global fileprivate

struct LocalMethodMacroBox
{
    base: s32
}

#[Swag.Macro]
func aliasBounceOuterReceiver(value: s32)->s32
{
    #macro
    {
        let #alias0 = #up value
        #macro
        {
            return #up buffer + 1
        }
    }
}

impl LocalMethodMacroBox
{
    #[Swag.Macro]
    mtd localNestedUpOuterReceiver(delta: s32)->s32
    {
        func pick(buffer: s32)->s32
        {
            return aliasBounceOuterReceiver(|buffer| #up me.base + #up delta)
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
