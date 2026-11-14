#global private

#[Swag.NoInline, Swag.Optimize(false)]
func reference(outerLimit, stopAt: s64)->s64
{
    let limit   = outerLimit < 4096 ? outerLimit : 4096
    var counter = 0's64
    var total   = 0's64
    var rounds  = 0's64
    while counter + 4 <= limit and rounds < 64
    {
        let remaining = limit - counter
        let bound     = remaining < 258 ? remaining : 258
        var matched   = 0's64
        while matched < bound
        {
            if matched == stopAt do
                break
            matched += 1
        }

        var best = 0's64
        if matched > best do
            best = matched
        total ^= counter % 32768
        if best >= 4 do
            counter += best
        else do
            counter += 1
        rounds += 1
    }

    return total ^ counter ^ rounds
}

#[Swag.NoInline, Swag.Optimize(true)]
func optimized(outerLimit, stopAt: s64)->s64
{
    let limit   = outerLimit < 4096 ? outerLimit : 4096
    var counter = 0's64
    var total   = 0's64
    var rounds  = 0's64
    while counter + 4 <= limit and rounds < 64
    {
        let remaining = limit - counter
        let bound     = remaining < 258 ? remaining : 258
        var matched   = 0's64
        while matched < bound
        {
            if matched == stopAt do
                break
            matched += 1
        }

        var best = 0's64
        if matched > best do
            best = matched
        total ^= counter % 32768
        if best >= 4 do
            counter += best
        else do
            counter += 1
        rounds += 1
    }

    return total ^ counter ^ rounds
}

#[Swag.NoInline, Swag.Optimize(true)]
func signedRemainder(value: s64)->s64 => value % 32768

#[Swag.NoInline, Swag.Optimize(false)]
func referenceRemainder(value: s64)->s64 => value % 32768

#test
{
    for limit in [-100's64, 0, 1, 4, 15, 40, 1024, 4096, 65536, 9223372036854775807]
    {
        for stopAt in [-1's64, 0, 1, 3, 4, 257, 258, 300] do
            Swag.require(optimized(limit, stopAt) == reference(limit, stopAt))
    }

    for value in [-9223372036854775808's64, -65537, -32769, -32768, -1, 0, 1, 32767, 32768, 65537, 9223372036854775807] do
        Swag.require(signedRemainder(value) == referenceRemainder(value))
}
