#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// Lowering computes the address of every operand before it loads any of them,
// so an indexed address reaches its load across the other operand's address.
// Folding the address into the load must keep reading the element it named,
// whether the loop counter, the base or the other operand changes in between.

#[Swag.Optimize(true), Swag.NoInline]
func dot(a, b: const [*] s32, count: u64)->s32
{
    var total = 0's32
    for i in count do
        total += a[i] * b[i]
    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func crossDifference(a, b: const [*] s64, count: u64)->s64
{
    var total = 0's64
    for i in 1 until count do
        total += a[i] * b[i - 1] - a[i - 1] * b[i]
    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func mixWords(dst: [*] u32, src: const [*] u32, count: u64)
{
    for i in count do
        dst[i] = (dst[i] ^ src[count - 1 - i]) + src[i]
}

#test
{
    let a = [1's32, -2, 3, 4, 5]
    let b = [6's32, 7, -8, 9, 10]
    Swag.assert(dot(&a[0], &b[0], 5) == 6 - 14 - 24 + 36 + 50)
    Swag.assert(dot(&a[0], &a[0], 5) == 1 + 4 + 9 + 16 + 25)
    Swag.assert(dot(&a[0], &b[0], 0) == 0)

    let x = [1's64, 2, 3, 4]
    let y = [5's64, 7, 11, 13]
    Swag.assert(crossDifference(&x[0], &y[0], 4) == (2 * 5 - 1 * 7) + (3 * 7 - 2 * 11) + (4 * 11 - 3 * 13))

    var d = [1'u32, 2, 3, 4]
    let s = [10'u32, 20, 30, 40]
    mixWords(&d[0], &s[0], 4)
    Swag.assert(d[0] == (1 ^ 40) + 10)
    Swag.assert(d[1] == (2 ^ 30) + 20)
    Swag.assert(d[2] == (3 ^ 20) + 30)
    Swag.assert(d[3] == (4 ^ 10) + 40)
}
