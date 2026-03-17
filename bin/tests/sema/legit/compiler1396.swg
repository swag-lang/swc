#global fileprivate // swc-option sema-only
#global skip
namespace A
{
    func toto()
    {
        //titi()
    }

    func titi()
    {
        toto()
    }
}
