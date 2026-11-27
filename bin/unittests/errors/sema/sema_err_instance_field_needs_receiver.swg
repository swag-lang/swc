#global private

// A bare field name reads the current receiver. A function without 'me' has none to read.
struct ReceiverFieldHolder
{
    value: s32
}

impl ReceiverFieldHolder
{
    func withoutReceiver()->s32 => value     // swc-expected-error {{instance field 'value' of 'ReceiverFieldHolder' needs a receiver, but this function has none; [help] declare the function with 'mtd', or read the field through a 'ReceiverFieldHolder' value}}

    mtd fromLocalFunction()->s32
    {
        func local()->s32 => value     // swc-expected-error {{sema_err_instance_field_needs_receiver}}
        return local()
    }

    mtd fromFunctionLiteral()->s32
    {
        let read = func() => value     // swc-expected-error {{instance field 'value' of 'ReceiverFieldHolder' needs a receiver, but this function literal has none; [help] capture the receiver with 'func|me|' and read 'me.value'}}
        return read()
    }

    mtd fromCapture()->u64
    {
        let read = func|me|() => me.value
        return cast(u64, read()) + #sizeof(value)
    }
}
