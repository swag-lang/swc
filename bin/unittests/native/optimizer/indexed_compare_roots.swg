#global private

// A comparison of two indexed bytes, 'data[a + l] == data[b + l]', adds the loop index to two
// offsets that do not change inside the loop. Both sums fold into an address rooted before
// the loop, the one feeding the comparison's memory operand as well as the one feeding its
// register operand, although the read of the second sits between the first sum and its use.

#[Swag.NoInline]
#[Swag.Optimize(true)]
func matchLength(data: const [*] u8, a, b, limit: s64)->s64
{
    var l = 0's64
    while l < limit and data[a + l] == data[b + l] do
        l += 1
    return l
}

// The candidate changes on every outer trip and is fixed for the inner loop.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func bestMatch(data: const [*] u8, cands: const [*] s64, count: s64, at, limit: s64)->s64
{
    var best = 0's64
    for k in count
    {
        let cand = cands[k]
        var l    = 0's64
        while l < limit and data[cand + l] == data[at + l] do
            l += 1
        if l > best do
            best = l
    }

    return best
}

#test
{
    let text = "abcabcabxabcabcabcd--abcabcabcabcx"
    var bytes: [34] u8
    for i in text.count do
        bytes[i] = text[i]
    let data = cast(const [*] u8) &bytes[0]
    Swag.assert(matchLength(data, 0, 3, 6) == 5)
    Swag.assert(matchLength(data, 0, 9, 10) == 8)
    Swag.assert(matchLength(data, 9, 21, 12) == 9)
    Swag.assert(matchLength(data, 3, 12, 4) == 4)
    Swag.assert(matchLength(data, 0, 1, 5) == 0)
    Swag.assert(matchLength(data, 21, 24, 9) == 9)

    let cands: [5] s64 = [0, 3, 9, 12, 18]
    Swag.assert(bestMatch(data, &cands[0], 5, 24, 9) == 9)
    Swag.assert(bestMatch(data, &cands[0], 2, 27, 6) == 6)
    Swag.assert(bestMatch(data, &cands[0], 0, 27, 6) == 0)
}
