#global private

// A slice, a string, or a struct taken by value reaches the callee as an address, and the
// callee cannot write through it. Reads of the parameter are therefore fixed for the whole
// call: they leave a loop that stores through another pointer, and repeat an earlier read
// across such a store. Every function is forced to the optimizing backend, and the results
// must match the unoptimized semantics.

struct Body
{
    x, y:  f64
    vx, vy: f64
    mass:  f64
}

struct Scale
{
    factor: s64
    bias:   s64
    limit:  u64
}

// The slice header is read once: the stores go through the pointer it holds, never to it.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func advance(bodies: [..] Body, dt: f64)
{
    for i in bodies.count
    {
        let bi = &bodies[i]
        for j in i + 1 until bodies.count
        {
            let bj = &bodies[j]
            let dx = bi.x - bj.x
            let dy = bi.y - bj.y
            bi.vx -= dx * bj.mass * dt
            bi.vy -= dy * bj.mass * dt
            bj.vx += dx * bi.mass * dt
            bj.vy += dy * bi.mass * dt
        }
    }

    for &b in bodies
    {
        b.x += dt * b.vx
        b.y += dt * b.vy
    }
}

// The destination is written on every trip; the text pointer and length stay in registers.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func upperInto(dst: [*] u8, text: string)->u64
{
    var count = 0'u64
    for i in text.count
    {
        var c = text[i]
        if c >= 'a'u8 and c <= 'z'u8
        {
            c -= 32
            count += 1
        }

        dst[i] = c
    }

    return count
}

// Three fields of a struct parameter, read around stores to the output.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func scaleInto(dst: [*] s64, src: const [*] s64, scale: Scale)->s64
{
    var total = 0's64
    for i in scale.limit
    {
        dst[i] = src[i] * scale.factor + scale.bias
        total += dst[i] + scale.bias
    }

    return total
}

// The call between the two reads may run anything; the parameter still holds its value.
var GCalls: u64

#[Swag.NoInline]
func touch(value: u64)
{
    GCalls += value
}

#[Swag.NoInline]
#[Swag.Optimize(true)]
func countAround(text: string)->u64
{
    var total = text.count
    for i in text.count
    {
        touch(cast(u64) text[i])
        total += text.count
    }

    return total
}

// A string handed on to a callee is still the caller's immutable value: the loop bound stays
// in a register although the text goes out as an argument on every trip.
#[Swag.NoInline]
func byteAt(text: string, index: u64)->u64
{
    GCalls += 1
    return cast(u64) text[index]
}

#[Swag.NoInline]
#[Swag.Optimize(true)]
func sumForwarded(dst: [*] u64, text: string)->u64
{
    var total = 0'u64
    for i in text.count
    {
        dst[i] = byteAt(text, i)
        total += dst[i] + text.count
    }

    return total
}

// An array parameter is a view of the caller's storage: the callee writes through it, and
// the reads that follow must see those writes.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func prefixSums(values: [6] s64)->s64
{
    for i in 1 until 6 do
        values[i] += values[i - 1]
    return values[5] + values[0]
}

// A parameter whose address is taken is read through that address too.
#[Swag.NoInline]
func fieldSum(scale: const *Scale)->s64 => scale.factor + scale.bias

#[Swag.NoInline]
#[Swag.Optimize(true)]
func sumThroughAddress(dst: [*] s64, scale: Scale)->s64
{
    var total = 0's64
    for i in scale.limit
    {
        dst[i] = fieldSum(&scale)
        total += dst[i] + scale.factor
    }

    return total
}

#test
{
    var bodies: [3] Body = [
        {0.0, 0.0, 0.0, 0.0, 4.0},
        {2.0, 1.0, 0.5, 0.0, 1.0},
        {-1.0, 3.0, 0.0, -0.25, 2.0}]
    advance(bodies, 0.5)
    Swag.assert(bodies[0].x == 0.0 and bodies[0].y == 1.75)
    Swag.assert(bodies[0].vx == 0.0 and bodies[0].vy == 3.5)
    Swag.assert(bodies[1].x == -1.25 and bodies[1].y == 1.0)
    Swag.assert(bodies[1].vx == -6.5 and bodies[1].vy == 0.0)
    Swag.assert(bodies[2].x == 0.75 and bodies[2].y == -0.625)
    Swag.assert(bodies[2].vx == 3.5 and bodies[2].vy == -7.25)

    var upper: [16] u8
    let raised = upperInto(&upper[0], "swag, 2026!")
    Swag.assert(raised == 4)
    Swag.assert(upper[0] == 'S'u8 and upper[3] == 'G'u8 and upper[4] == ','u8 and upper[10] == '!'u8)

    let src: [4] s64 = [1, -2, 3, 40]
    var dst: [4] s64
    let scaled = scaleInto(&dst[0], &src[0], {3, 5, 4})
    Swag.assert(scaled == 166)
    Swag.assert(dst[0] == 8 and dst[1] == -1 and dst[2] == 14 and dst[3] == 125)

    GCalls = 0
    let counted = countAround("abc")
    Swag.assert(counted == 12)
    Swag.assert(GCalls == 294)

    var forwarded: [4] u64
    GCalls = 0
    let forwardedSum = sumForwarded(&forwarded[0], "abc")
    Swag.assert(forwardedSum == 303 and GCalls == 3)
    Swag.assert(forwarded[0] == 97 and forwarded[2] == 99 and forwarded[3] == 0)

    var values: [6] s64 = [1, 2, 3, 4, 5, 6]
    let summed = prefixSums(values)
    Swag.assert(summed == 22)
    Swag.assert(values[1] == 3 and values[5] == 21)

    let addressed = sumThroughAddress(&dst[0], {7, -2, 3})
    Swag.assert(addressed == 36)
    Swag.assert(dst[0] == 5 and dst[2] == 5 and dst[3] == 125)
}
