// Migrated from the former native/legit suite.
#global fileprivate
using Swag

// _compiler115.swg
namespace compiler115
{
    //
    #test
    {
        var v = 10's8 + 2.0'f64
        @assert(v == 12.0)
    }
}

// _compiler1580.swg
namespace compiler1580
{
    //
    #test
    {
        enum Color
        {
            Red
            Green
            Blue
        }
    
        let a = Color.Green
        @assert(a == 1)
    }
    
    func toto()->bool { return true }
    
    #test
    {
        @assert(toto())
    }
}

// _compiler1629.swg
namespace compiler1629
{
    //
    #test
    {
        var arr: [64] u8
        var ptr  = cast([*] [*] void) &arr[0]
        ptr[0] = null
        @assert(ptr[0] == null)
    }
}

// _compiler1633.swg
namespace compiler1633
{
    //
    struct A
    {
        x:     u32
        y:     u32
    }
    
    #test
    {
        var st: A
        //st.y = 0
        @assert(st.x == 0)
        @assert(st.y == 0)
    }
}

// _compiler1637.swg
namespace compiler1637
{
    //
    struct A
    {
        x:     u32
        y:     u32
    }
    
    #test
    {
        var st: A
        st.y = 0
        @assert(st.y == 0)
    }
}

// _compiler1638.swg
namespace compiler1638
{
    //
    //#global testerror
    
    struct A
    {
        x:     u32
        y:     u32
    }
    
    #test
    {
        var st: A
        st.y = 0
        @assert(st.y == 0)
    }
}

// _compiler1640.swg
namespace compiler1640
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var c: [*] u8 = null
        c += 0xFF00
        var usedBuckets: u32
        usedBuckets = c ? 1 : 0
        @assert(usedBuckets == 1)
    }
}

// _compiler1648.swg
namespace compiler1648
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var x = 0xFFFFFFFF'u64
        x %= 16'u32
    
        let m: u32 = 16
        x %= cast(u64) m
        @assert(x == 15)
    }
}

// _compiler1651.swg
namespace compiler1651
{
    //
    //#[Swag.PrintBc]
    func toto1(x: any)->s32
    {
        let v = cast(s32) x
        @assert(v == 100)
        return v
    }
    
    #test
    {
        @assert(toto1(100) == 100)
    }
}

// _compiler1653.swg
namespace compiler1653
{
    //
    func toto(x: ...)->u64 { return @countof(x) }
    
    func toto1(x: u32...)->u64 { return @countof(x) }
    
    #test
    {
        @assert(toto() == 0)
        @assert(toto1() == 0)
    }
}

// _compiler1659.swg
namespace compiler1659
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let precision: u32 = 5
        let roundValue = 0.5 / (10 * precision)
        @assert(roundValue == 0.01)
    }
}

// _compiler1661.swg
namespace compiler1661
{
    //
    struct TT
    {
        value: s64 = 456
    }
    
    //#[Swag.PrintBc]
    #test
    {
        var addr:  [1] **TT
        var addr1: *TT
        var value: TT
    
        addr[0] = &addr1
        //addr1[0] = &value
    
        //@print(addr[0].value)
        @assert(addr[0] == &addr1)
    }
}

// _compiler1662.swg
namespace compiler1662
{
    //
    struct TT
    {
        value: s64 = 456
    }
    
    //#[Swag.PrintBc]
    #test
    {
        var addr:  [1] [*] [*] s64
        var addr1: [*] s64
        var value: s64 = 666
    
        addr[0] = cast([*] [*] s64) &addr1
        addr1   = cast([*] s64) &value
    
        @assert(addr[0][0][0] == 666)
    }
}

// _compiler1663.swg
namespace compiler1663
{
    //
    struct TT
    {
        value: s64 = 456
    }
    
    //#[Swag.PrintBc]
    #test
    {
        var addr:  [1] [*] [*] TT
        var addr1: [*] TT
        var value: TT
    
        addr[0] = cast([*] [*] TT) &addr1
        addr1   = cast([*] TT) &value
    
        //@print(addr1.value)
        @assert(addr[0][0].value == 456)
    }
}

// _compiler1664.swg
namespace compiler1664
{
    //
    struct TT
    {
        value: s64 = 456
    }
    
    //#[Swag.PrintBc]
    #test
    {
        var addr:  [2, 2] *TT
        var value: TT
    
        addr[0, 0] = &value
    
        //@print(addr[0,0].value)
        @assert(addr[0, 0].value == 456)
    }
}

// _compiler1666.swg
namespace compiler1666
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
    }
    
    //#[Swag.PrintBc]
    func C(x: ...)
    {
        let ptr1 = cast(TT) x[0]
        //@print(cast(s64) ptr1.value)
        @assert(ptr1.value == 456)
    }
    
    #test
    {
        var x: TT
        C(x)
        @assert(x.value == 456)
    }
}

// _compiler1668.swg
namespace compiler1668
{
    //
    func function(x: s32, y: s32 = 100)->s32
    {
        @assert(x == 50)
        @assert(y == 100)
        return y
    }
    
    #test
    {
        let ptr = &function
        @assert(ptr(50) == 100)
    }
}

// _compiler1669.swg
namespace compiler1669
{
    //
    func function(x: s32, y: ...)->u64
    {
        @assert(x == 50)
        return @countof(y)
    }
    
    #test
    {
        let ptr = &function
        @assert(ptr(50) == 0)
    }
}

// _compiler167.swg
namespace compiler167
{
    //
    #test
    {
        @assert(1 == 1)
    }
    
    #test
    {
        @assert(2 > 1)
    }
    
    #test
    {
        @assert(!false)
    }
}

// _compiler1671.swg
namespace compiler1671
{
    //
    //
    //#global testerror
    
    //#[Swag.PrintBc]
    func toto(x: ...)->typeinfo
    {
        @assert(@kindof(x[0]) == s32)
        return @kindof(x[0])
    }
    
    #test
    {
        @assert(toto(5) == s32)
    }
}

// _compiler1677.swg
namespace compiler1677
{
    //
    struct TT
    {
        value:  s64 = 456
        value1: s64 = 456
        value2: s64 = 456
    }
    
    func C(x: const &TT)->s64
    {
        @assert(x.value == 456)
        return x.value
    }
    
    #test
    {
        var x: TT
        @assert(C(x) == 456)
    }
}

// _compiler1678.swg
namespace compiler1678
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
    }
    
    func D(x: TT)->s64
    {
        //@print(cast(s64) x.value)
        @assert(x.value == 456)
        return x.value
    }
    
    //#[Swag.PrintBc]
    func C(x: any)->s64
    {
        return D(cast(TT) x)
    }
    
    #test
    {
        var x: TT
        @assert(C(x) == 456)
    }
}

// _compiler1679.swg
namespace compiler1679
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
        value3:     s64 = 456
        value4:     s64 = 456
    }
    
    //#[Swag.PrintBc]
    func D(x: ...)->s64
    {
        return E(x[0])
    }
    
    //#[Swag.PrintBc]
    func E(x: any)->s64
    {
        let ptr = cast(TT) x
        //C(cast(TT) x)
        return C(ptr)
    }
    
    //#[Swag.PrintBc]
    func C(x: TT)->s64
    {
        //@print(cast(s64) x.value)
        @assert(x.value == 456)
        return x.value
    }
    
    #test
    {
        var x: TT
        @assert(D(x) == 456)
    }
}

// _compiler1680.swg
namespace compiler1680
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
        value3:     s64 = 456
        value4:     s64 = 456
    }
    
    //#[Swag.PrintBc]
    func D(x: ...)->s64
    {
        return E(x[0])
    }
    
    //#[Swag.PrintBc]
    func E(x: any)->s64
    {
        return C(cast(TT) x)
    }
    
    //#[Swag.PrintBc]
    func C(x: TT)->s64
    {
        //@print(cast(s64) x.value)
        @assert(x.value == 456)
        return x.value
    }
    
    #test
    {
        var x: TT
        @assert(D(x) == 456)
    }
}

// _compiler1681.swg
namespace compiler1681
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
        value3:     s64 = 456
        value4:     s64 = 456
    }
    
    alias myStruct = TT
    
    //#[Swag.PrintBc]
    func C(x: myStruct)->s64
    {
        //@print(cast(s64) x.value)
        @assert(x.value == 456)
        return x.value
    }
    
    #test
    {
        var x: myStruct
        @assert(C(x) == 456)
    }
}

// _compiler1682.swg
namespace compiler1682
{
    //
    struct TT
    {
        value:      s64 = 456
        value1:     s64 = 456
        value2:     s64 = 456
        value3:     s64 = 456
        value4:     s64 = 456
    }
    
    alias myStruct = TT
    
    //#[Swag.PrintBc]
    func C(x: any)->s64
    {
        //@print(cast(s64) x.value)
        let val = cast(myStruct) x
        @assert(val.value == 456)
        return val.value
    }
    
    #test
    {
        var x: myStruct
        @assert(C(x) == 456)
    }
}

// _compiler1788.swg
namespace compiler1788
{
    //
    //#[Swag.PrintBc]
    #test
    {
        G += 1
        @assert(G == 1)
    }
    
    //#[Swag.PrintBc]
    #init
    {
        //@assert(G == 1)
    }
    
    var G: s64
}

// _compiler206.swg
namespace compiler206
{
    //
    #test
    {
        @assert(1 == 1)
        @assert(2 == 2)
    }
}

// _compiler208.swg
namespace compiler208
{
    //
    func main(a: s64)->s64
    {
        @assert(a == 666)
        return a
    }
    
    #test
    {
        @assert(main(666's64) == 666)
    }
}

// _compiler209.swg
namespace compiler209
{
    //
    func main(a: f64, b: f64)->f64
    {
        @assert(a == 666)
        @assert(b == 555)
        return a + b
    }
    
    #test
    {
        @assert(main(666'f64, 555'f64) == 1221.0)
    }
}

// _compiler218.swg
namespace compiler218
{
    //
    const g: s64 = 5
    const h  = 5555
    const i  = 1.5
    
    #test
    {
        @assert(g == 5)
        @assert(h == 5555)
        @assert(i == 1.5)
    }
}

// _compiler219.swg
namespace compiler219
{
    //
    #[ConstExpr]
    func main()->s32 { return 555; }
    
    const v = main()
    
    #test
    {
        @assert(v == 555)
    }
}

// _compiler221.swg
namespace compiler221
{
    //
    var v = 50
    
    #test
    {
        v = 6; v = (5 * 3) + 11;
        @assert(v == 26)
    }
}

// _compiler223.swg
namespace compiler223
{
    //
    var v = 50
    
    //#[PrintBc]
    func main()
    {
        @assert(v == 50)
        v = 666; @assert(v == 666)
    }
    
    #test
    {
        main()
        @assert(v == 666)
    }
}

// _compiler224.swg
namespace compiler224
{
    //
    var b0: bool = true
    var b1: u8 = 1
    var b2: u16 = 2
    var b3: u32 = 3
    var b4: u64 = 4
    
    //#[PrintBc]
    func main()
    {
        @assert(b0 == true)
        @assert(b1 == 1)
        @assert(b2 == 2)
        @assert(b3 == 3)
        @assert(b4 == 4)
    }
    
    #test
    {
        main()
        @assert(b0 == true)
        @assert(b4 == 4)
    }
}

// _compiler225.swg
namespace compiler225
{
    //
    var b0: bool = true
    var b1: u64 = 666
    var b2: f32 = 1.5
    
    //#[PrintBc]
    func main()
    {
        @assert(b0 == true)
        b0 = false; @assert(b0 == false)
    
        @assert(b1 == 666)
        b1 = 50; @assert(b1 == 50)
    
        @assert(b2 == 1.5)
        b2 = 1 + 3; @assert(b2 == 4.0)
    }
    
    #test
    {
        main()
        @assert(b0 == false)
        @assert(b1 == 50)
        @assert(b2 == 4.0)
    }
}

// _compiler227.swg
namespace compiler227
{
    //
    func main()->s32
    {
        var a: s32
        var b: s32
        a = 666; b = 100; @assert(a == 666)
        @assert(b == 100)
        a = 500; @assert(a == 500)
        @assert(b == 100)
        return a + b
    }
    
    //#[PrintBc]
    func main1()->s32
    {
        return main()
    }
    
    #test
    {
        @assert(main1() == 600)
    }
}

// _compiler228.swg
namespace compiler228
{
    //
    //#[PrintBc]
    func main()->s32
    {
        var a: s32
        {
            var b: s32
            a = 666; b = 100; }
        @assert(a == 666)
        return a
    }
    
    #test
    {
        @assert(main() == 666)
    }
}

// _compiler229.swg
namespace compiler229
{
    //
    //#[PrintBc]
    func main()->s64
    {
        let a: s32 = 666
        @assert(a == 666)
        let b: s64 = 555
        @assert(b == 555)
        return a + b
    }
    
    #test
    {
        @assert(main() == 1221)
    }
}

// _compiler231.swg
namespace compiler231
{
    //
    //#[PrintBc]
    func main()->f64
    {
        var a = 10
        a += 1; @assert(a == 11)
    
        var b = 1.0'f64
        b += 1.5'f64; @assert(b == 2.5)
        return cast(f64) a + b
    }
    
    #test
    {
        @assert(main() == 13.5)
    }
}

// _compiler234.swg
namespace compiler234
{
    //
    #test
    {
        var a = 1
        a *= 2; @assert(a == 2)
        a *= 2; @assert(a == 4)
    
        var b = 1.0'f32
        b /= 2; @assert(b == 0.5)
    }
}

// _compiler235.swg
namespace compiler235
{
    //
    //#[PrintBc]
    func main()->s32
    {
        var a = 0xFFFFFF45
        a &= 0xFF; @assert(a == 0x45)
        a |= 0x100; @assert(a == 0x145)
    
        var b = 0b1001
        b ^= 0b1111; @assert(b == 0b0110)
        return a + b
    }
    
    #test
    {
        @assert(main() == 331)
    }
}

// _compiler236.swg
namespace compiler236
{
    //
    func main()->s32
    {
        var a = 0b10101010
        a >>= 1; @assert(a == 0b1010101)
        a <<= 2; @assert(a == 0b101010100)
        return a
    }
    
    #test
    {
        @assert(main() == 0b101010100)
    }
}

// _compiler238.swg
namespace compiler238
{
    //
    //#[PrintBc]
    func main()->s32
    {
        var a = 1
        var b = 666
        a = b; @assert(a == 666)
        b = 10; a += b; @assert(a == 676)
        return a
    }
    
    #test
    {
        @assert(main() == 676)
    }
}

// _compiler246.swg
namespace compiler246
{
    //
    //#[PrintBc]
    func main(a: s32 = 6)->s32
    {
        @assert(a == 6)
        return a
    }
    
    //#[PrintBc]
    func main1()->s32
    {
        return main()
    }
    
    #test
    {
        @assert(main1() == 6)
    }
}

// _compiler249.swg
namespace compiler249
{
    //
    #[ConstExpr]
    func value()->s32 { return 55; }
    
    func main(a: s32 = value())->s32
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

// _compiler287.swg
namespace compiler287
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: bool = true
        let b  = &a
        let c  = dref b
        @assert(c == true)
    }
    
    #test
    {
        var a: s32 = 666
        let b  = &a
        let c  = dref b
        @assert(c == 666)
    }
}

// _compiler310.swg
namespace compiler310
{
    //
    var g = false
    
    //#[Swag.PrintBc]
    #test
    {
        g = false; @assert(g == false)
        g = true; @assert(g == true)
        //@print(g);
    }
}

// _compiler322.swg
namespace compiler322
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: s32 = 666
        let b  = &a
        var c: *s32
        c = b; @assert(dref b == 666)
        @assert(dref c == 666)
        /*@assert(a == 1);
    	b[0] = 666;
    	@assert(a == 666);*/
    }
}

// _compiler323.swg
namespace compiler323
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: s32 = 1
        var b  = &a
        dref b = 666; @assert(a == 666)
        @assert(dref b == a)
    }
}

// _compiler324.swg
namespace compiler324
{
    //
    //#[Swag.PrintMicro]
    #test
    {
        var a: [4] s32
        a[0] = 1; a[1] = 2; a[2] = 20; a[3] = 30; @assert(a[0] == 1)
        @assert(a[1] == 2)
        @assert(a[2] == 20)
        @assert(a[3] == 30)
    }
}

// _compiler332.swg
namespace compiler332
{
    //
    //#[Swag.PrintBc]
    #test
    {
        var a: [2] s32 = [50, 60]
        let b  = 666
        @assert(a[0] == 50)
        @assert(a[1] == 60)
        @assert(b == 666)
    }
}

// _compiler333.swg
namespace compiler333
{
    //
    var a: [2] s32 = [50, 60]
    
    //#[Swag.PrintBc]
    #test
    {
        @assert(a[0] == 50)
        @assert(a[1] == 60)
    }
}

// _compiler335.swg
namespace compiler335
{
    //
    #test
    {
        @assert(16 == 4 * 2 * 2)
        @assert(16 == 16)
    }
}

// _compiler339.swg
namespace compiler339
{
    //
    #test
    {
        var a: [2, 2] s32
        a[0, 0] = 1
        a[0, 1] = 2
        a[1, 0] = 3
        a[1, 1] = 4
        @assert(a[0, 0] + a[0, 1] + a[1, 0] + a[1, 1] == 10)
    }
}

// _compiler340.swg
namespace compiler340
{
    //
    #test
    {
        var a: [2, 2] s32 = [[1, 2], [3, 4]]
        @assert(a[0, 0] == 1)
        @assert(a[0, 1] == 2)
        @assert(a[1, 0] == 3)
        @assert(a[1, 1] == 4)
        @assert(a[0, 0] + a[0, 1] + a[1, 0] + a[1, 1] == 10);
    }
}

// _compiler342.swg
namespace compiler342
{
    //
    #test
    {
        var a   = 0
        var b   = 0
        let pa1 = &a
        let pa2 = &a
        let pb  = &b
        @assert(pa1 == pa2)
        @assert(pb > pa1)
        @assert(pa1 < pb)
        @assert(pb >= pa1)
        @assert(pa1 <= pb)
        @assert(pa1 != pb)
    }
}

// _compiler343.swg
namespace compiler343
{
    //
    //#[Swag.PrintBc]
    #test
    {
        let a: *s32 = null
        @assert(a == null)
    }
}

// _compiler344.swg
namespace compiler344
{
    //
    #test
    {
        var a: s32
        @assert(a == 0)
        var b: *s32
        @assert(b == null)
    }
}


