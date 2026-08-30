// Migrated from the former native/legit suite.
#global private
using Swag

// _compiler1387.swg
namespace compiler1387
{
    //
    #test
    {
        var count = 0
        while false
        {
            count += 1
        }
        Swag.assert(count == 0)
    }
}

// _compiler213.swg
namespace compiler213
{
    //
    #test
    {
        var state = 0
        if true
        {
            state += 1
        }

        if true
        {
            state += 10
        }

        if 1 + 1 == 2 + 1
        {
            state += 100
        }
        else
        {
            state += 1000
        }
        Swag.assert(state == 1011)
    }
}

// _compiler216.swg
namespace compiler216
{
    //
    func main()->bool
    {
        if false
        {
            Swag.assert(false)
        }
        else
        {
            Swag.assert(true)
        }

        Swag.assert(true)
        return true
    }

    #test
    {
        Swag.assert(main())
    }
}

// _compiler230.swg
namespace compiler230
{
    //
    func main()->s32
    {
        var a = 10
        var b = 0
        while (a > 0)
        {
            a = a - 1; b = b + 1;
        }

        Swag.assert(a == 0)
        Swag.assert(b == 10)
        return b
    }

    #test
    {
        Swag.assert(main() == 10)
    }
}

// _compiler241.swg
namespace compiler241
{
    //
    func main()->s32
    {
        var a = 10
        while a > 0
        {
            a -= 1; if (a == 5) do
                break
            continue
        }
        Swag.assert(a == 5)
        return a
    }

    #test
    {
        Swag.assert(main() == 5)
    }
}

// _compiler242.swg
namespace compiler242
{
    //
    #[Swag.Warning("sema_warn_unreachable_code", .Disable)]
    func main()->s32
    {
        var a = 0
        while a < 10
        {
            a += 1;
            {
                {
                    break
                }
            }
            Swag.assert(false)
        }

        Swag.assert(a == 1)
        return a
    }

    #test
    {
        Swag.assert(main() == 1)
    }
}

// _compiler243.swg
namespace compiler243
{
    //
    func toto()->s32
    {
        var a = 0
        while a < 10
        {
            a += 1
            for
            {
                break
            }
        }

        Swag.assert(a == 10)
        return a
    }

    #test
    {
        Swag.assert(toto() == 10)
    }
}

// _compiler256.swg
namespace compiler256
{
    //
    #test
    {
        var i = 5
        while i > 0
        {
            i -= 1;
        }

        Swag.assert(i == 0)
    }
}

// _compiler260.swg
namespace compiler260
{
    //
    func fact(v: s32)->s32
    {
        if v == 1 do
            return 1
        let res = fact(v - 1) * v
        return res
    }

    #test
    {
        Swag.assert(fact(5) == 120)
        Swag.assert(fact(4) == 24)
        Swag.assert(fact(3) == 6)
        Swag.assert(fact(2) == 2)
        Swag.assert(fact(1) == 1)
    }
}

// _compiler262.swg
namespace compiler262
{
    //
    func fact(v: s32)->s32
    {
        if (v == 1) do
            return 1
        let res = v * fact(v - 1)
        return res
    }

    #test
    {
        Swag.assert(fact(5) == 120)
        Swag.assert(fact(4) == 24)
        Swag.assert(fact(3) == 6)
        Swag.assert(fact(2) == 2)
        Swag.assert(fact(1) == 1)
    }
}

// _compiler265.swg
namespace compiler265
{
    //
    func test2(v: s32)->s32
    {
        if (v == 1) do
            return 1
        return v * test1(v - 1)
    }

    func test1(v: s32)->s32
    {
        if (v == 1) do
            return 1
        return v * test2(v - 1)
    }

    #test
    {
        Swag.assert(test2(5) == 120)
        Swag.assert(test2(4) == 24)
    }
}

// _compiler303.swg
namespace compiler303
{
    //
    /*
    func compare (str1: string, str2: string)-> bool
    {
	var count1 = str1.count;
	var count2 = str2.count;
    	if(count1 != count2)
    		return false;
    
	Swag.print(cast(s32) count1);
	var src = str1.buffer;
	var dst = str2.buffer;
    	while(src[0] != 0)
    	{
    		if(src[0] != dst[0])
    			return false;
    		src += 1;
    		dst += 1;
    	}
    
    	return true;
    }*/

    func compare(str: string)
    {
        let count = str.count
        Swag.assert(count == 4)
    }

    #test
    {
        compare("toto")
        Swag.assert(("toto").count == 4)
    }
}

// _compiler304.swg
namespace compiler304
{
    //
    var g:  bool = true
    var g1: s32  = 666
    var g2: u64  = 0xF000_000F

    /*
    func compare: (str1: string, str2: string)-> bool
    {
	var count1 = str1.count;
	var count2 = str2.count;
    	if(count1 != count2)
    		return false;
    
	Swag.print(cast(s32) count1);
	var src = str1.buffer;
	var dst = str2.buffer;
    	while(src[0] != 0)
    	{
    		if(src[0] != dst[0])
    			return false;
    		src += 1;
    		dst += 1;
    	}
    
    	return true;
    }*/

    #test
    {
        Swag.assert(g == true)
        Swag.assert(g1 == 666)
        Swag.assert(g2 == 0xF000_000F)
    }
}

// _compiler314.swg
namespace compiler314
{
    //
    func len(str: string)->u32
    {
        var p = str.buffer
        var l = 0'u32
        while p[0] != 0
        {
            l += 1
            p += 1
        }

        Swag.assert(l == str.count)
        return l
    }

    #test
    {
        Swag.assert(len("toto") == 4)
        Swag.assert(len("tonton") == 6)
    }
}
