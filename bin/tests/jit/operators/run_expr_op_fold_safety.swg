#global fileprivate

#test
{
    #[Swag.Optimize(true)]
    func foldDivZeroCipher()->s32
    {
        var lhs: s32 = 126
        var rhs: s32 = 7
        rhs ^= rhs
        return lhs / rhs // swc-expected-error {{safety_err_division_zero}}
    }

    const V = #run foldDivZeroCipher()
}

#test
{
    #[Swag.Optimize(true)]
    func foldModZeroCipher()->u32
    {
        var lhs: u32 = 126'u32
        var rhs: u32 = 9'u32
        rhs ^= rhs
        return lhs % rhs // swc-expected-error {{safety_err_division_zero}}
    }

    const V = #run foldModZeroCipher()
}

#test
{
    #[Swag.Optimize(true)]
    func foldDivOverflowCipher()->s32
    {
        var lhs: s32 = -2147483648's32
        var rhs: s32 = -1
        return lhs / rhs // swc-expected-error {{safety_err_integer_overflow}}
    }

    const V = #run foldDivOverflowCipher()
}
