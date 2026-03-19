// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler1382.swg
namespace compiler1382
{
    //
    func toto()->bool { return true }
    
    #test
    {
        @assert(toto())
    }
}

// _compiler150.swg
namespace compiler150
{
    //
    #test
    {
        @assert(main())
    }
    
    func main()->bool
    {
        return true
    }
}

// _compiler1647.swg
namespace compiler1647
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var arr:  [12] u8
        let cpt   = 3'u32
        let slice = cast([..] u8) @mkslice(&arr[0], cast(u64) cpt)
        @assert(@countof(slice) == 3)
    }
}

// _compiler165.swg
namespace compiler165
{
    //
    func main()->bool
    {
        @assert(true)
        return true
    }
    
    #test
    {
        @assert(main())
    }
}

// _compiler1675.swg
namespace compiler1675
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let s   = 1
        var res = false
        switch s
        {
        case 1:
            fallthrough
        case 2:
            res = true
        }
        @assert(res)
    }
}

// _compiler1676.swg
namespace compiler1676
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let s   = 1
        var res = false
        switch s
        {
        case 1:
            fallthrough
        case 2:
            fallthrough
        case 3:
            res = true
        }
        @assert(res)
    }
}

// _compiler168.swg
namespace compiler168
{
    //
    #test
    {
        @assert(((2's64 + 4) * 2) == 12)
    }
}

// _compiler210.swg
namespace compiler210
{
    //
    //#[PrintBc]
    func main(a: s32)->s32
    {
        return a + 1
    }
    
    #test
    {
        @assert(main(6) == 7)
        @assert(main(4 + 6) == 11)
    }
}

// _compiler211.swg
namespace compiler211
{
    //
    func main(a: s32)->s32
    {
        return a + 1
    }
    
    #test
    {
        @assert(main(main(6)) == 8)
        @assert(main(main(main(6))) == 9)
    }
}

// _compiler217.swg
namespace compiler217
{
    //
    //#[PrintBc]
    func main(a: s32)->s32
    {
        return a + 1
    }
    
    //#[PrintBc]
    func main1()
    {
        @assert(main(6) == 7)
        @assert(main(4 + 6) == 11)
    }
    
    #test
    {
        main1()
        @assert(main(6) == 7)
    }
}

// _compiler226.swg
namespace compiler226
{
    //
    //#[PrintBc]
    func main()->bool
    {
        var a: s32
        {
            var b: s64
            var c: s64
        }
        {
            var b: s64
        }
        return true
    }
    
    //#[PrintBc]
    func main1()->bool
    {
        return main()
    }
    
    #test
    {
        @assert(main1())
    }
}

// _compiler257.swg
namespace compiler257
{
    //
    func test1()->s32 { return 666; }
    
    #test
    {
        @assert(test1() == 666)
    }
}

// _compiler258.swg
namespace compiler258
{
    //
    func test1(a: s32, b: s32)->s32
    {
        return a - b
    }
    
    #test
    {
        @assert(test1(60, 40) == 20)
        @assert(test1(50, 50) == 0)
        @assert(test1(50, 60) == -10)
    }
}

// _compiler259.swg
namespace compiler259
{
    //
    func test1(a: f32, b: f32)->f32
    {
        return a - b
    }
    
    #test
    {
        @assert(test1(60.0, 40.0) == 20)
        @assert(test1(50.0, 50.0) == 0)
        @assert(test1(50.0, 60.0) == -10)
    }
}

// _compiler284.swg
namespace compiler284
{
    //
    //#[Swag.PrintBc]
    func main()->bool
    {
        var v:  bool = false
        var p1: *s32 = cast(*s32) &v
        return p1 == cast(*s32) &v
    }
    
    #test
    {
        @assert(main())
    }
}

// _compiler307.swg
namespace compiler307
{
    //
    func toto()->bool { return true; }
    func toto1()->bool { return true; }
    
    #test
    {
        @assert(toto() == toto1())
    }
}


