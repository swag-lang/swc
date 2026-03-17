#global fileprivate // swc-option sema-only
#global skip
#[Swag.Compiler]
func toto()
{
    const X = [10, 10, 20, 40]
    @print(X[0])
}
