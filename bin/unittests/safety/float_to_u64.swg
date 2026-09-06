#global private

// Invalid inputs remain guarded before the unsigned conversion is lowered.
#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f32)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(18_446_744_073_709_551_616.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f32)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(-1.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f64)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(-1.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f32)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(cast #bit(f32) 0x7FC0_0000'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f64)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(cast #bit(f64) 0x7FF8_0000_0000_0000'u64)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f32)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(cast #bit(f32) 0x7F80_0000'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func convert(value: f64)->u64
    {
        return cast(u64) value     // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run convert(cast #bit(f64) 0x7FF0_0000_0000_0000'u64)
}
