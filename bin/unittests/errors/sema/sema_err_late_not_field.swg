#global private

func lateLocal()
{
    var value: #late *s32 // swc-expected-error {{sema_err_late_not_field}}
    @print(value)
}
