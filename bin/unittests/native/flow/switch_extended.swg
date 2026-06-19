#global fileprivate

// Switch with negative values
#test
{
    var v: s32 = -3
    var hit = 0
    switch v
    {
        case -5:
            hit = 1
            break
        case -3:
            hit = 2
            break
        case 0:
            hit = 3
            break
        default:
            hit = 4
            break
    }
    @assert(hit == 2)
}

// Switch with negative range
#test
{
    var v: s32 = -2
    var hit = 0
    switch v
    {
        case -5 to -1:
            hit = 1
            break
        case 0 to 5:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 1)
}

// Switch hitting default
#test
{
    var v = 999
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 2:
            hit = 2
            break
        default:
            hit = 99
            break
    }
    @assert(hit == 99)
}

// Switch with no matching case and no default (hit is 0)
#test
{
    var v = 999
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 2:
            hit = 2
            break
    }
    @assert(hit == 0)
}

// Multiple switch statements in sequence
#test
{
    var a = 1
    var b = 2
    var ra = 0
    var rb = 0
    switch a
    {
        case 1:
            ra = 10
            break
        default:
            ra = 0
            break
    }
    switch b
    {
        case 2:
            rb = 20
            break
        default:
            rb = 0
            break
    }
    @assert(ra == 10)
    @assert(rb == 20)
}

// Switch inside for loop
#test
{
    var sum = 0
    for i in 5
    {
        switch cast(s32) i
        {
            case 0:
                sum += 1
                break
            case 1:
                sum += 10
                break
            case 2:
                sum += 100
                break
            default:
                sum += 1000
                break
        }
    }
    // i=0: 1, i=1: 10, i=2: 100, i=3: 1000, i=4: 1000
    @assert(sum == 2111)
}

// Switch with multiple values including negative
#test
{
    var v: s32 = -1
    var hit = 0
    switch v
    {
        case -1, 0, 1:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

// Nested switch
#test
{
    var a = 1
    var b = 2
    var hit = 0
    switch a
    {
        case 1:
            switch b
            {
                case 1:
                    hit = 11
                    break
                case 2:
                    hit = 12
                    break
                default:
                    hit = 19
                    break
            }
            break
        case 2:
            hit = 20
            break
        default:
            hit = 99
            break
    }
    @assert(hit == 12)
}

// Switch on u8 type
#test
{
    var v: u8 = 255
    var hit = 0
    switch v
    {
        case 0:
            hit = 1
            break
        case 255:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

// Switch with range at boundaries
#test
{
    var v = 3
    var hit = 0
    switch v
    {
        case 1 to 3:
            hit = 1
            break
        case 4 to 6:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 1) // 3 is in 1 to 3 inclusive
}

// Switch on function return
func getChoice()->s32 { return 2 }
#test
{
    var hit = 0
    switch getChoice()
    {
        case 1:
            hit = 1
            break
        case 2:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

// Switch where clause with variable from outer scope
#test
{
    var mode = 1
    var v = 5
    var hit = 0
    switch v
    {
        case 5 where mode == 1:
            hit = 1
            break
        case 5 where mode == 2:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 1)
}

// Switch where clause falling through to default
#test
{
    var mode = 99
    var v = 5
    var hit = 0
    switch v
    {
        case 5 where mode == 1:
            hit = 1
            break
        case 5 where mode == 2:
            hit = 2
            break
    }
    @assert(hit == 0)
}
