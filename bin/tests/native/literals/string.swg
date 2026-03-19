// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler1643.swg
namespace compiler1643
{
    //
    //#[Swag.PrintBc]
    #test
    {
        const tbl = "0123456789ABCDEF"
        var c     = tbl[0]
        //@print(cast(s64) c)
        @assert(tbl[0] == cast(u8) '0''rune)
        @assert(tbl[1] == cast(u8) '1''rune)
    }
}

// _compiler1644.swg
namespace compiler1644
{
    //
    //#[Swag.PrintBc]
    #test
    {
        const tbl = "0123456789ABCDEF"
        let x     = 1
        let c     = tbl[x]
        @assert(c == cast(u8) '1''rune)
    }
}

// _compiler1654.swg
namespace compiler1654
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let s   = "%%"
        let ptr = @dataof(s)
        @assert(ptr[0] == cast(u8) '%''rune)
    }
}

// _compiler1673.swg
namespace compiler1673
{
    //
    //
    //#global testerror
    
    //#[Swag.PrintBc]
    func toto(x: ...)->typeinfo
    {
        @assert(@kindof(x[0]).fullname == "s32")
        return @kindof(x[0])
    }
    
    #test
    {
        @assert(toto(5) == s32)
    }
}

// _compiler169.swg
namespace compiler169
{
    //
    #[ConstExpr]
    func main()->s32
    {
        //@print("toto\n");
        return 666
    }
    
    #test
    {
        var r = main()
        @assert(r == 666)
    }
}

// _compiler247.swg
namespace compiler247
{
    //
    //#[PrintBc]
    #[Swag.Overload]
    func main(a: s32 = 6)->s32
    {
        //@print("1");
        return a
    }
    
    #[Swag.Overload]
    func main(a: s32, b: s32)->s32
    {
        //@print("2");
        return b
    }
    
    func main1()
    {
        @assert(main() == 6)
        @assert(main(5) == 5)
        @assert(main(5, 7) == 7)
    }
    
    #test
    {
        main1()
        @assert(main(5, 7) == 7)
    }
}

// _compiler291.swg
namespace compiler291
{
    //
    //#[PrintBc]
    func test2(v: string, v1: string)->bool
    {
        //@print(v);
        //@print(v1);
        return v == "toto" and v1 == "titi"
    }
    
    //#[PrintBc]
    #test
    {
        @assert(test2("toto", "titi"))
    }
}

// _compiler292.swg
namespace compiler292
{
    //
    //#[PrintBc]
    #test
    {
        let b = "abcd"
        @assert(b[0] == cast(u8) 'a''rune)
        @assert(b[1] == cast(u8) 'b''rune)
        @assert(b[2] == cast(u8) 'c''rune)
        @assert(b[3] == cast(u8) 'd''rune)
    }
}

// _compiler293.swg
namespace compiler293
{
    //
    //#[PrintBc]
    #test
    {
        let b = "XYZ"
        @assert(b[2] == cast(u8) 'Z''rune)
    }
}

// _compiler297.swg
namespace compiler297
{
    //
    //#[Swag.PrintBc]
    func test1()->string
    {
        return "toto1"
    }
    
    #test
    {
        let c = test1()
        @assert(c == "toto1")
    }
}

// _compiler298.swg
namespace compiler298
{
    //
    //#[PrintBc]
    func test2()->string
    {
        return "toto1"
    }
    
    //#[PrintBc]
    #test
    {
        var res = test2()
        //@op(res, count) == 5;
    
        //@print(res);
        //@print(test2.count);
        @assert(res == "toto1")
        @assert(@countof(res) == 5)
    }
}

// _compiler299.swg
namespace compiler299
{
    //
    //#[PrintBc]
    #test
    {
        @assert(@countof("toto") == 4)
        @assert(@countof("totototo") == 8)
    }
}

// _compiler301.swg
namespace compiler301
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var str = "toto"
        var c   = @countof(str)
        @assert(c == 4)
    
        str = "totototo"; c   = @countof(str); @assert(c == 8)
    }
}

// _compiler302.swg
namespace compiler302
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let str = "ABCD"
        let p:  const [*] u8 = @dataof(str)
        @assert(p[0] == cast(u8) 'A''rune)
        @assert(p[1] == cast(u8) 'B''rune)
        @assert(p[2] == cast(u8) 'C''rune)
        @assert(p[3] == cast(u8) 'D''rune)
    }
}

// _compiler308.swg
namespace compiler308
{
    //
    var g = "toto"
    
    //#[Swag.PrintBc]
    #test
    {
        let c = @countof(g)
        @assert(c == 4)
    }
}

// _compiler309.swg
namespace compiler309
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let c = "toto"
        @assert(c == "toto")
        @assert(c != "titi")
    }
}

// _compiler311.swg
namespace compiler311
{
    //
    var g: string
    
    //#[Swag.PrintBc]
    #test
    {
        g = "toto"; @assert(g == "toto")
        g = "titi"; @assert(g == "titi")
        //@print(g);
    }
}


