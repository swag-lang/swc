// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler1387.swg
namespace compiler1387
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var count = 0
        while false
        {
            count += 1
        }
        @assert(count == 0)
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
        @assert(state == 1011)
    }
}

// _compiler216.swg
namespace compiler216
{
    //
    //#[PrintBc]
    func main()->bool
    {
        if false
        {
            @assert(false)
        }
        else
        {
            @assert(true)
        }
    
        @assert(true)
        return true
    }
    
    #test
    {
        @assert(main())
    }
}

// _compiler230.swg
namespace compiler230
{
    //
    //#[PrintBc]
    func main()->s32
    {
        var a = 10
        var b = 0
        while (a > 0)
        {
            a = a - 1; b = b + 1; }
    
        @assert(a == 0)
        @assert(b == 10)
        return b
    }
    
    #test
    {
        @assert(main() == 10)
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
        @assert(a == 5)
        return a
    }
    
    #test
    {
        @assert(main() == 5)
    }
}

// _compiler242.swg
namespace compiler242
{
    //
    //#[PrintBc]
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
            @assert(false)
        }
    
        @assert(a == 1)
        return a
    }
    
    #test
    {
        @assert(main() == 1)
    }
}

// _compiler243.swg
namespace compiler243
{
    //
    //#[PrintBc]
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
    
        @assert(a == 10)
        return a
    }
    
    #test
    {
        @assert(toto() == 10)
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
            i -= 1; }
    
        @assert(i == 0)
    }
}

// _compiler260.swg
namespace compiler260
{
    //
    //#[PrintBc]
    func fact(v: s32)->s32
    {
        if v == 1 do
            return 1
        let res = fact(v - 1) * v
        return res
    }
    
    #test
    {
        @assert(fact(5) == 120)
        @assert(fact(4) == 24)
        @assert(fact(3) == 6)
        @assert(fact(2) == 2)
        @assert(fact(1) == 1)
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
        @assert(fact(5) == 120)
        @assert(fact(4) == 24)
        @assert(fact(3) == 6)
        @assert(fact(2) == 2)
        @assert(fact(1) == 1)
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
    
    //#[Swag.PrintBc]
    func test1(v: s32)->s32
    {
        if (v == 1) do
            return 1
        return v * test2(v - 1)
    }
    
    #test
    {
        @assert(test2(5) == 120)
        @assert(test2(4) == 24)
    }
}

// _compiler303.swg
namespace compiler303
{
    //
    /*
    func compare (str1: string, str2: string)-> bool
    {
    	var count1 = @countof(str1);
    	var count2 = @countof(str2);
    	if(count1 != count2)
    		return false;
    
    	@print(cast(s32) count1);
    	var src = @dataof(str1);
    	var dst = @dataof(str2);
    	while(src[0] != 0)
    	{
    		if(src[0] != dst[0])
    			return false;
    		src += 1;
    		dst += 1;
    	}
    
    	return true;
    }*/
    
    //#[Swag.PrintBc]
    func compare(str: string)
    {
        let count = @countof(str)
        @assert(count == 4)
    }
    
    //#[Swag.PrintBc]
    #test
    {
        compare("toto")
        @assert(@countof("toto") == 4)
    }
}

// _compiler304.swg
namespace compiler304
{
    //
    var g:  bool = true
    var g1: s32 = 666
    var g2: u64 = 0xF000_000F
    
    /*
    func compare: (str1: string, str2: string)-> bool
    {
    	var count1 = @countof(str1);
    	var count2 = @countof(str2);
    	if(count1 != count2)
    		return false;
    
    	@print(cast(s32) count1);
    	var src = @dataof(str1);
    	var dst = @dataof(str2);
    	while(src[0] != 0)
    	{
    		if(src[0] != dst[0])
    			return false;
    		src += 1;
    		dst += 1;
    	}
    
    	return true;
    }*/
    
    //#[Swag.PrintBc]
    #test
    {
        @assert(g == true)
        @assert(g1 == 666)
        @assert(g2 == 0xF000_000F)
    }
}

// _compiler314.swg
namespace compiler314
{
    //
    func len(str: string)->u32
    {
        var p = @dataof(str)
        var l = 0'u32
        while p[0] != 0
        {
            l += 1
            p += 1
        }
    
        @assert(l == @countof(str))
        return l
    }
    
    #test
    {
        @assert(len("toto") == 4)
        @assert(len("tonton") == 6)
    }
}


