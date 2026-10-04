#global private

// An unreachable fallback still has to belong to the left operand's value family.
func incompatiblePointer(value: *s32, fallback: *u64?)
{
    discard value orelse fallback     // swc-expected-error {{sema_err_cannot_cast}}
}

func incompatibleString(value: string, fallback: *s32?)
{
    discard value orelse fallback     // swc-expected-error {{sema_err_cannot_cast}}
}
