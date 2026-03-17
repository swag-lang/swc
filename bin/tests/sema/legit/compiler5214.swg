#global fileprivate // swc-option sema-only
#global skip
struct Err {}

//#[Swag.PrintBc]
func toto() throw
{
    throw Err{}
}

//#[Swag.PrintBc]
#test
{
    catch
    {
        toto()
        toto()
    }
}
