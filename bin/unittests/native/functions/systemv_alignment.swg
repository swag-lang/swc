#global private

#static if #os == Swag.TargetOs.Linux
{
    #[Swag.Align(32)]
    struct Aligned32 { values: [4]u64 }
    #[Swag.Align(64)]
    struct Aligned64 { values: [8]u64 }
    #[Swag.Align(128)]
    struct Aligned128 { values: [16]u64 }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func sum32(value: Aligned32)->u64
    {
        Swag.assert(cast(u64, &value) % 32 == 0)
        var result: u64
        for entry in value.values do result += entry
        return result
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func sum64(value: Aligned64)->u64
    {
        Swag.assert(cast(u64, &value) % 64 == 0)
        var result: u64
        for entry in value.values do result += entry
        return result
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func sum128(value: Aligned128)->u64
    {
        Swag.assert(cast(u64, &value) % 128 == 0)
        var result: u64
        for entry in value.values do result += entry
        return result
    }

    #test
    {
        Swag.assert(sum32(Aligned32{[11, 23, 37, 53]}) == 124)
        var medium: Aligned64
        for &entry, index in medium.values do entry[] = index + 1
        Swag.assert(sum64(medium) == 36)
        var large: Aligned128
        for &entry, index in large.values do entry[] = index + 1
        Swag.assert(sum128(large) == 136)
    }

    #[Swag.CallingConvention(.C)]
    alias AlignedCallback = func(Aligned64)->u64

    #[Swag.NoInline]
    func invokeAligned(callback: AlignedCallback, value: Aligned64)->u64
    {
        return callback(value)
    }

    #test
    {
        let value = Aligned64{[1, 3, 5, 7, 11, 13, 17, 19]}
        Swag.assert(invokeAligned(&sum64, value) == 76)
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func mixAligned(a, b, c, d, e, f, g: u64, first: Aligned32, x: f64, second: Aligned128, tail: u64)->f64
    {
        Swag.assert(cast(u64, &first) % 32 == 0)
        Swag.assert(cast(u64, &second) % 128 == 0)
        return cast(f64, a + b + c + d + e + f + g + tail + sum32(first) + sum128(second)) + x
    }

    #test
    {
        var large: Aligned128
        for &entry, index in large.values do entry[] = index + 1
        let result = mixAligned(1, 2, 3, 4, 5, 6, 7, Aligned32{[11, 23, 37, 53]}, 0.5, large, 41)
        Swag.assert(result == 329.5)
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func returnedAligned(value: Aligned32)->Aligned128
    {
        Swag.assert(cast(u64, &value) % 32 == 0)
        var result: Aligned128
        for &entry, index in result.values do entry[] = value.values[index % 4] + index
        return result
    }

    #test
    {
        let source = Aligned32{[11, 23, 37, 53]}
        let result = returnedAligned(source)
        for entry, index in result.values do
            Swag.assert(entry == source.values[index % 4] + index)
    }

    #[Swag.Align(32)]
    struct AlignedOwner
    {
        value: u64
        drops: *u64
    }

    impl AlignedOwner
    {
        mtd opDrop() { .drops[] += 1 }
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func readOwned(value: AlignedOwner)->u64
    {
        Swag.assert(cast(u64, &value) % 32 == 0)
        return value.value
    }

    #[Swag.CallingConvention(.C), Swag.NoInline]
    func makeOwned(value: u64, drops: *u64)->AlignedOwner
    {
        return AlignedOwner{value, drops}
    }

    #test
    {
        var drops: u64
        Swag.assert(readOwned(AlignedOwner{41, &drops}) == 41)
        Swag.assert(drops == 1)
        Swag.assert(readOwned(makeOwned(43, &drops)) == 43)
        Swag.assert(drops == 2)
        scope
        {
            let owner = AlignedOwner{47, &drops}
            Swag.assert(readOwned(owner) == 47 and drops == 2)
        }
        Swag.assert(drops == 3)
    }
}
