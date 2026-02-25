#global internal

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
