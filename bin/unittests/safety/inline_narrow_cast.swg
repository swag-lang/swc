#global private

#[Swag.Inline]
func narrow(value: u32)->u16
{
    return cast(u16) value // swc-expected-error {{safety_err_runtime}}
}

#test
{
    const value = #run narrow(0x10000)
}
