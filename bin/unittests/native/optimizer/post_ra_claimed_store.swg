#global private

// A post-RA immediate fold can claim the spill store that a later forwarding
// pattern inspects. The reload must observe the folded immediate, never the
// register whose materialization the first pattern removes.
#[Swag.NoInline]
func sumTwelve(a, b, c, d, e, f, g, h, i, j, k, l: u64)->u64
{
    return a + b + c + d + e + f + g + h + i + j + k + l
}

#[Swag.Optimize(true)]
func keepClaimedStoreReload(seed: u64)->u64
{
    let a      = seed + 1
    let b      = seed + 2
    let c      = seed + 3
    let d      = seed + 4
    let e      = seed + 5
    let f      = seed + 6
    let g      = seed + 7
    let h      = seed + 8
    let i      = seed + 9
    let j      = seed + 10
    let k      = seed + 11
    let marker = 17'u64

    let first  = sumTwelve(a, b, c, d, e, f, g, h, i, j, k, marker)
    let second = sumTwelve(marker, k, j, i, h, g, f, e, d, c, b, a)
    return first + second
}

#test
{
    Swag.assert(keepClaimedStoreReload(100) == 2366)
}
