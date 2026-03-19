// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler1064.swg
namespace compiler1064
{
    //#[Swag.ConstExpr]
    //#[Swag.PrintBc]
    func fibonacci(num: s32)->s32
    {
        if num < 2 do
            return num
        else do
            return fibonacci(num - 1) + fibonacci(num - 2)
    }
    
    var fibonacciOfAge: s32 = #run fibonacci(16)
    
    #test
    {
        @assert(fibonacciOfAge == 987)
    }
}

// _compiler1386.swg
namespace compiler1386
{
    //
    enum A
    {
        AA
    }
    
    enum B
    {
        BB
    }
    
    #test
    {
        using A, B
        @assert(#typeof(A.AA) != #typeof(B.BB))
    }
}

// _compiler1504.swg
namespace compiler1504
{
    //
    var X: u32 = undefined
    
    #[Swag.Compiler]
    func set()
    {
        X = 6
    }
    
    //#[Swag.PrintBc]
    #test
    {
        #run set()
        @assert(X == 6)
    }
}

// _compiler1505.swg
namespace compiler1505
{
    #[Swag.Compiler]
    func set(x: string)
    {
        @assert(x == "inside function set")
        //@print(x)
    }
    
    //#[Swag.PrintBc]
    #test
    {
        #run
        {
            let x = "inside function set"
            set(x)
        }
    }
}

// _compiler1506.swg
namespace compiler1506
{
    #[Swag.Compiler]
    func set(x: string)
    {
        @assert(x == "inside function set")
        //@print(x)
    }
    
    //#[Swag.PrintBc]
    #test
    {
        #run
        {
            let x = "inside function set"
            set(x)
        }
    }
}

// _compiler1599.swg
namespace compiler1599
{
    #[Swag.Compiler]
    func toto()->bool
    {
        return true
    }
    
    #test
    {
        #assert(#run toto()
    )
    }
}

// _compiler1665.swg
namespace compiler1665
{
    //
    //
    //#global testerror
    
    struct TT
    {
        x, y, z:  s64 = 456
    }
    
    //#[Swag.PrintBc]
    func C(x: ...)
    {
        var ptr1 = cast(const & TT) x[0]
        var ptr2 = cast(TT) x[0]
        @assert(ptr1.x == 456)
        @assert(ptr2.y == 456)
        ptr2.x = 100
        @assert(ptr1.x == 456)
    
        /*@print(@kindof(x[0]).name); @print("\n")
        @print(#typeof(ptr1).name); @print("\n")
        @print(#typeof(ptr2).name); @print("\n")*/
        //ptr1.value = 0
    }
    
    #test
    {
        var x: TT
        C(x)
        @assert(x.x == 456)
    }
}

// _compiler1667.swg
namespace compiler1667
{
    //
    //
    //#global testerror
    
    struct TT
    {
        value: s64 = 456
    }
    
    //#[Swag.PrintBc]
    func C(x: ...)
    {
        //@print(#typeof(x[0]).name)
        //var ptr1 = cast(const TT) x[0]
        //ptr1.value = 456
    }
    
    #test
    {
        var x: TT
        C(x)
        @assert(x.value == 456)
    }
}

// _compiler1672.swg
namespace compiler1672
{
    //
    //
    //#global testerror
    
    //#[Swag.PrintBc]
    func toto(x: ...)->typeinfo
    {
        return #typeof(x[0])
    }
    
    #test
    {
        @assert(toto(5) == any)
    }
}

// _compiler1888.swg
namespace compiler1888
{
    //#[Swag.PrintBc]
    func toto(x: s64)
    {
        @assert(x == 666)
    }
    
    //#[Swag.PrintBc]
    func titi()
    {
        const x = 666's64
        #run toto(x)
    }
}

// _compiler1893.swg
namespace compiler1893
{
    //#[Swag.PrintBc]
    func toto(x: s64)
    {
        @assert(x == 666)
    }
    
    //#[Swag.PrintBc]
    func titi(x: bool)
    {
        #run
        {
            let x = 666's64
            toto(x)
        }
    }
}

// _compiler239.swg
namespace compiler239
{
    //
    func main1()->s32 { return 77; }
    
    #[ConstExpr]
    func main2()->s32 { return 666; }
    
    func main()
    {
        let a = #run main1()
        //let b = main1()
        //let c = main2()
        @assert(a == 77)
        //@assert(b == 77)
        //@assert(c == 666)
    }
    
    #test
    {
        main()
        @assert(main1() == 77)
    }
}

// _compiler2407.swg
namespace compiler2407
{
    #[Swag.Inline]
    public func toto2407()
    {
        #run
        {
            var x = 4
        }
    }
}

// _compiler2447.swg
namespace compiler2447
{
    //#global skip
    func N() => 10
    
    #assert(#typeof(N()) == #typeof(10))
    #assert(#typeof(#run N()) == #typeof(10))
    
    const ArrCount = cast(s32) #run N()
    var arr: [ArrCount] s32
    
    #test
    {
        @assert(@countof(arr) == 10)
    }
}

// _compiler250.swg
namespace compiler250
{
    //
    func value()->s32 { return 55; }
    
    func main(a: s32 = #run value()
    )->s32
    {
        return a
    }
    
    //#[PrintBc]
    func main1()
    {
        @assert(main() == 55)
    }
    
    #test
    {
        main1()
        @assert(main() == 55)
    }
}

// _compiler2634.swg
namespace compiler2634
{
    //
    #[Compiler]
    var G = 0
    
    #[Compiler]
    func toto()->s32
    {
        for 10 do
            G += 1
    
        return G
    }
    
    #assert(#run toto() == 10)
}

// _compiler295.swg
namespace compiler295
{
    //
    #test
    {
        @assert(#sizeof(bool) == 1)
        @assert(#sizeof(s8) == 1)
        @assert(#sizeof(s16) == 2)
        @assert(#sizeof(s32) == 4)
        @assert(#sizeof(s64) == 8)
        @assert(#sizeof(u8) == 1)
        @assert(#sizeof(u16) == 2)
        @assert(#sizeof(u32) == 4)
        @assert(#sizeof(u64) == 8)
        @assert(#sizeof(f32) == 4)
        @assert(#sizeof(f64) == 8)
        @assert(#sizeof(rune) == 4)
        @assert(#sizeof(string) == 8 + 8)
    }
}

// _compiler2957.swg
namespace compiler2957
{
    #[Swag.ConstExpr]
    struct V { x, y, z: f32 = 666 }
    
    func toto()->V
    {
        return {1, 2, 3}
    }
    
    const C = #run toto()
    #assert(C.x == 1)
    #assert(C.y == 2)
    #assert(C.z == 3)
}

// _compiler2959.swg
namespace compiler2959
{
    #[Swag.ConstExpr]
    struct V { x, y: f32 = 0 }
    
    func toto(x, y: V)->V
    {
        return {x.x + y.x, x.y + y.y}
    }
    
    const C = #run toto({1, 2}, {10, 20})
    #assert(C.x == 11)
    #assert(C.y == 22)
}

// _compiler296.swg
namespace compiler296
{
    //
    #test
    {
        @assert(#sizeof(*bool) == 8)
        @assert(#sizeof(1's32) == 4)
        @assert(#sizeof(1'u64) == 8)
        @assert(#sizeof(1.0'f32) == 4)
        @assert(#sizeof(1.0'f64) == 8)
        @assert(#sizeof(5 * 4's32) == 4)
    }
}

// _compiler2979.swg
namespace compiler2979
{
    //
    #[Swag.Compiler]
    const X: [2] s32 = [10, 20]
    
    #[Swag.Optimize(false), Swag.Compiler]
    func test()->bool
    {
        let val = X[1]
        return val == 20 and X[1] == 20
    }
    
    #assert(#run test())
}

// _compiler3029.swg
namespace compiler3029
{
    //#global skip
    func toto(x, y: s32)->{ x: s32, y: s32 }
    {
        var result: retval
        result.x = x * x
        result.y = y * y * y
        return result
    }
    
    //#[Swag.PrintBc]
    #test
    {
        let (x1, y1) = #run toto(2, 2)
        @assert(x1 == 4)
        @assert(y1 == 8)
    }
}

// _compiler3100.swg
namespace compiler3100
{
    //#global skip
    
    //#global testerror
    
    func msg() => "msg"
    
    #test
    {
        var x = 1
        #if false do
            #error(#run msg())
    }
}

// _compiler3120.swg
namespace compiler3120
{
    #[Swag.Compiler]
    func mySillyFunction()->string
    {
        return "666"
    }
    
    #test
    {
        const Msg = #run mySillyFunction()
        @assert(Msg == "666")
    }
}

// _compiler3121.swg
namespace compiler3121
{
    //
    #[Swag.Compiler]
    func titi()->bool { return true }
    
    #assert(#run titi())
}

// _compiler3324.swg
namespace compiler3324
{
    //#global skip
    //#global testerror
    #test
    {
        let a = #run
        {
            var ret = 0's32
            for 10 do
                ret += 66
            return ret
        }
    
        @assert(a == 660)
    }
}

// _compiler3325.swg
namespace compiler3325
{
    //#global testerror
    #test
    {
        #[Swag.Compiler]
        func init()->u64
        {
            var sum = 0'u64
            for i in 3
            {
                var T: typeinfo = undefined
                switch i
                {
                case 0:
                    T = f32
                case 1:
                    T = s8
                case 2:
                    T = bool
                }
    
                sum += @countof(T.name)
            }
    
            return sum
        }
    
        const A = #run init()
        #assert(A == 9)
    }
}

// _compiler334.swg
namespace compiler334
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: [2, 2] s32
        //@assert(#sizeof(a) == 2'u32 * 2'u32 * #sizeof(s32));
        @assert(#sizeof(a) == 16)
        var b: [5, 5] bool
        @assert(#sizeof(b) == 25)
    }
}

// _compiler3374.swg
namespace compiler3374
{
    struct A {}
    impl A
    {
        #run
        {
        }
    }
}

// _compiler345.swg
namespace compiler345
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: s32 = undefined
        var b: *s32 = undefined
        @assert(#typeof(a) == s32)
        @assert(#typeof(b) == *s32)
    }
}

// _compiler350.swg
namespace compiler350
{
    //#[Swag.PrintBc]
    #test
    {
        const a = 666
        let b   = #run a
        @assert(b == 666)
    }
}

// _compiler4101.swg
namespace compiler4101
{
    const C = #run @compiler.getBuildCfg().backendKind
}

// _compiler4102.swg
namespace compiler4102
{
    //#[Swag.ConstExpr]
    struct A { x: s32 }
    func toto()->A { return A{1}; }
    
    const C = #run toto()
    #assert(C.x == 1)
}

// _compiler4104.swg
namespace compiler4104
{
    const CFG: Swag.BuildCfg = #run dref @compiler.getBuildCfg()
}

// _compiler4266.swg
namespace compiler4266
{
    func isThisRelease()->bool
    {
        return true
    }
    
    #if #run isThisRelease() == false
    {
        #warning("this should not be called !")
    }
}

// _compiler4844.swg
namespace compiler4844
{
    #test
    {
        const N           = 4
        const PowerOfTwo: [N] s32 = #run
        {
            var arr: [N] s32
            for i in arr do
                arr[i] = 1 << cast(u32) i
            return arr
        }
    
        #assert(PowerOfTwo[0] == 1)
        #assert(PowerOfTwo[1] == 2)
        #assert(PowerOfTwo[2] == 4)
        #assert(PowerOfTwo[3] == 8)
    }
}

// _compiler4845.swg
namespace compiler4845
{
    #test
    {
        const PowerOfTwo = #run
        {
            return [1, 2, 3, 4]
        }
        #assert(PowerOfTwo[0] == 1)
        #assert(PowerOfTwo[3] == 4)
    }
}

// _compiler4847.swg
namespace compiler4847
{
    //#global testerror "Err0023"
    #test
    {
        const PowerOfTwo: [4] s32 = #run
        {
            let a = 1
            let b = a + 1
            return [a, b, 3, 4]
        }
        #assert(PowerOfTwo[0] == 1)
        #assert(PowerOfTwo[1] == 2)
        #assert(PowerOfTwo[3] == 4)
    }
}

// _compiler4848.swg
namespace compiler4848
{
    //#global testerror "Err0023"
    struct RGB { a, b, c: s32 }
    
    #test
    {
        const X: RGB = #run
        {
            return RGB{1, 2, 3}
        }
        #assert(X.a == 1)
        #assert(X.b == 2)
        #assert(X.c == 3)
    }
}

// _compiler4849.swg
namespace compiler4849
{
    const MyString: string = #run
    {
        var str: [3] u8
        str[0] = 'a'
        str[1] = 'b'
        str[2] = str[1] + 1
        return cast(string) str
    }
    
    #assert(MyString == "abc")
    
    struct Carrier
    {
        item: any
        other: any
    }
    
    #test
    {
        let value = #run
        {
            var payload: Carrier
            payload.item = "abc"
            payload.other = "def"
            return payload
        }
    
        let values = #run
        {
            var words: [2] any
            words[0] = "first"
            words[1] = "second"
            return words
        }
    
        @assert(cast(string) value.item == "abc")
        @assert(cast(string) value.other == "def")
        @assert(cast(string) values[0] == "first")
        @assert(cast(string) values[1] == "second")
    }
}


