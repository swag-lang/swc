#global fileprivate // swc-option sema-only
#global skip
using Swag

#[Inline]
func toto()
{
    func titi() {}

    titi()
}

#[Inline]
func tata()
{
    toto()
}

#test
{
    tata()
}
