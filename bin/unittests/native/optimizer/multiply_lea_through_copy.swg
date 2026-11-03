#global private
using Swag

// A sum of two registers becomes one address computation, and a multiply by
// three of its copy becomes another, reading the sum through the copy. Both
// rewrites once landed in the same sweep: the first retargeted the sum onto
// the copy's destination and erased the copy, the second still named the
// erased register. The offset came out as zero.

#[Swag.Optimize(true)]
func pixelOffset(i: u64)->u64
{
    const Width  = 17'u64
    const Height = 2'u64
    let sourceY = i / Width
    let x       = i % Width
    let targetY = Height - sourceY - 1
    return (targetY * Width + x) * 3
}

#[Swag.Optimize(true)]
func scaledSum(a, b: u64)->u64
{
    let sum = a + b
    return sum * 5 + sum * 9
}

#test
{
    Swag.require(pixelOffset(17) == 0)
    Swag.require(pixelOffset(5) == 66)
    Swag.require(pixelOffset(0) == 51)
    Swag.require(pixelOffset(33) == 48)
    Swag.require(scaledSum(3, 4) == 98)
    Swag.require(scaledSum(100, 23) == 1722)
}
