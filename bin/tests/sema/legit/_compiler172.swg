#global fileprivate // swc-option sema-only
#[Swag.ConstExpr]
func main()->s32
{
    return 666
}

#assert(main() == 666)
#assert(main() == 666)
