#global private

#[Swag.CallingConvention(.C)]
alias CCallback = func(s32)->s32

func swagCallback(value: s32)->s32 => value

func takesCCallback(callback: CCallback) {}

#test
{
    takesCCallback(cast(&swagCallback))     // swc-expected-error {{sema_err_cannot_cast}}
}
