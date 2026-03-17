#global fileprivate // swc-option sema-only
#global skip
//#global testerror

#[Swag.ConstExpr]
func isInteger(type: typeinfo) => true

func(var A) add()
    where isInteger(A)
{
}

#test
{
    add's32()
}
