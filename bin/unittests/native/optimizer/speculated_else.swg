#global private

// A branch between a load and a constant or a register sets the cheap value
// before the branch and skips the load. In range and out of range, with a
// constant, a zero or another register in the cheap arm, every width must
// read what the branch selects.

#[Swag.Optimize(true), Swag.NoInline]
func getOr0(p: const [*] s32, n, i: u64)->s32 => i < n ? p[i] : 0
#[Swag.Optimize(true), Swag.NoInline]
func getOrMinus(p: const [*] s64, n, i: u64)->s64 => i < n ? p[i] : -1
#[Swag.Optimize(true), Swag.NoInline]
func getOrFallback(p: const [*] u32, n, i: u64, fallback: u32)->u32 => i < n ? p[i] : fallback
#[Swag.Optimize(true), Swag.NoInline]
func byteOr7(p: const [*] u8, n, i: u64)->u32 => i >= n ? 7 : cast(u32) p[i]

#test
{
    let a: [3] s32 = [10, -20, 30]
    let b: [3] s64 = [1, 2, 3]
    let c: [3] u32 = [4, 5, 6]
    let d: [3] u8  = [200, 1, 2]
    for i in 5
    {
        let inside = i < 3
        Swag.assert(getOr0(&a[0], 3, i) == (inside ? a[i] : 0))
        Swag.assert(getOrMinus(&b[0], 3, i) == (inside ? b[i] : -1))
        Swag.assert(getOrFallback(&c[0], 3, i, 99) == (inside ? c[i] : 99))
        Swag.assert(byteOr7(&d[0], 3, i) == (inside ? cast(u32) d[i] : 7))
    }
}
