// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler163.swg
namespace compiler163
{
    //
    using A.B
    
    namespace A.B
    {
        func main()->bool { return true }
    }
    
    #test
    {
        @assert(main())
    }
}

// _compiler1650.swg
namespace compiler1650
{
    //
    func aa(x: u32, y: any) {}
    
    namespace aa1650
    {
        struct B {}
    }
    
    //#[Swag.PrintBc]
    #test
    {
        let x = #typeof(aa1650.B)
        let y = #typeof(bool)
        if (x == y)
        {
            @assert(false)
        }
    }
}


