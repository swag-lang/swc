// Migrated from the former native/legit suite.
#global private
using Swag

// _compiler1643.swg
namespace compiler1643
{
    //
    #test
    {
        const tbl = "0123456789ABCDEF"
        var c = tbl[0]
        // Swag.print(cast(s64) c)
        Swag.assert(tbl[0] == cast(u8) '0'rune)
        Swag.assert(tbl[1] == cast(u8) '1'rune)
    }
}

// _compiler1644.swg
namespace compiler1644
{
    //
    #test
    {
        const tbl = "0123456789ABCDEF"
        let x = 1
        let c = tbl[x]
        Swag.assert(c == cast(u8) '1'rune)
    }
}

// _compiler1654.swg
namespace compiler1654
{
    //
    #test
    {
        let s   = "%%"
        let ptr = s.buffer
        Swag.assert(ptr[0] == cast(u8) '%'rune)
    }
}

// _compiler1673.swg
namespace compiler1673
{
    //
    //

    func toto(x: ...)->typeinfo
    {
        Swag.assert(Swag.kindOf(x[0]).fullname == "s32")
        return Swag.kindOf(x[0])
    }

    #test
    {
        Swag.assert(toto(5) == s32)
    }
}

// _compiler169.swg
namespace compiler169
{
    //
    #[ConstExpr]
    func main()->s32
    {
        // Swag.print("toto\n");
        return 666
    }

    #test
    {
        var r = main()
        Swag.assert(r == 666)
    }
}

// _compiler247.swg
namespace compiler247
{
    //
    func main(a: s32 = 6)->s32
    {
        // Swag.print("1");
        return a
    }

    func main(a: s32, b: s32)->s32
    {
        // Swag.print("2");
        return b
    }

    func main1()
    {
        Swag.assert(main() == 6)
        Swag.assert(main(5) == 5)
        Swag.assert(main(5, 7) == 7)
    }

    #test
    {
        main1()
        Swag.assert(main(5, 7) == 7)
    }
}

// _compiler291.swg
namespace compiler291
{
    //
    func test2(v: string, v1: string)->bool
    {
        // Swag.print(v);
        // Swag.print(v1);
        return v == "toto" and v1 == "titi"
    }

    #test
    {
        Swag.assert(test2("toto", "titi"))
    }
}

// _compiler292.swg
namespace compiler292
{
    //
    #test
    {
        let b = "abcd"
        Swag.assert(b[0] == cast(u8) 'a'rune)
        Swag.assert(b[1] == cast(u8) 'b'rune)
        Swag.assert(b[2] == cast(u8) 'c'rune)
        Swag.assert(b[3] == cast(u8) 'd'rune)
    }
}

namespace cstring_index_runtime
{
    #test
    {
        var text: const cstring = cast(const cstring) ("abcd").buffer
        Swag.assert(text[0] == cast(u8) 'a'rune)
        Swag.assert(text[3] == cast(u8) 'd'rune)
    }

    #test
    {
        let value = (cast(const cstring) ("abcd").buffer)[2]
        Swag.assert(value == cast(u8) 'c'rune)
    }
}

// _compiler293.swg
namespace compiler293
{
    //
    #test
    {
        let b = "XYZ"
        Swag.assert(b[2] == cast(u8) 'Z'rune)
    }
}

// _compiler297.swg
namespace compiler297
{
    //
    func test1()->string
    {
        return "toto1"
    }

    #test
    {
        let c = test1()
        Swag.assert(c == "toto1")
    }
}

// _compiler298.swg
namespace compiler298
{
    //
    func test2()->string
    {
        return "toto1"
    }

    #test
    {
        var res = test2()
        // Swag.print(res);
        // Swag.print(test2.count);
        Swag.assert(res == "toto1")
        Swag.assert(res.count == 5)
    }
}

// _compiler299.swg
namespace compiler299
{
    //
    #test
    {
        Swag.assert(("toto").count == 4)
        Swag.assert(("totototo").count == 8)
    }
}

// _compiler301.swg
namespace compiler301
{
    //
    #test
    {
        var str = "toto"
        var c   = str.count
        Swag.assert(c == 4)

        str = "totototo"; c = str.count; Swag.assert(c == 8)
    }
}

// _compiler302.swg
namespace compiler302
{
    //
    #test
    {
        let str             = "ABCD"
        let p: const [*] u8 = str.buffer
        Swag.assert(p[0] == cast(u8) 'A'rune)
        Swag.assert(p[1] == cast(u8) 'B'rune)
        Swag.assert(p[2] == cast(u8) 'C'rune)
        Swag.assert(p[3] == cast(u8) 'D'rune)
    }
}

// _compiler308.swg
namespace compiler308
{
    //
    var g = "toto"

    #test
    {
        let c = g.count
        Swag.assert(c == 4)
    }
}

// _compiler309.swg
namespace compiler309
{
    //
    #test
    {
        let c = "toto"
        Swag.assert(c == "toto")
        Swag.assert(c != "titi")
    }
}

// _compiler311.swg
namespace compiler311
{
    //
    var g: string = ""

    #test
    {
        g = "toto"; Swag.assert(g == "toto")
        g = "titi"; Swag.assert(g == "titi")
    // Swag.print(g);
    }
}
