#global fileprivate // swc-option suite-test

#test
{
    var v = 2
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 2, 3:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    var hit = 0
    switch 1
    {
        case 1:
            hit += 1
            break
        default:
            hit += 10
            break
    }

    switch 1
    {
        case 1:
            hit += 100
            break
        default:
            hit += 1000
            break
    }
    @assert(hit == 101)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
    }

    var v : E = E.B
    var hit = 0
    switch v
    {
        case E.A:
            hit = 1
            break
        case .B:
            hit = 2
            break
        default:
            hit = 3
            break
    }
    @assert(hit == 2)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
        C = 3,
    }

    var v : E = .A
    @assert(v == .A)
}

#test
{
    enum E : s32
    {
        A = 1,
        B = 2,
    }

    var v : E = E.B
    var hit = 0
    switch v
    {
        case E.A:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 2)
}

#test
{
    alias MyInt = s32
    var v : MyInt = 3
    var hit = 0
    switch v
    {
        case 1:
            hit = 1
            break
        case 3:
            hit = 3
            break
        default:
            hit = 9
            break
    }
    @assert(hit == 3)
}

#test
{
    var v = 1.5
    var hit = 0
    switch v
    {
        case 1.5:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = true
    var hit = 0
    switch v
    {
        case true:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = "hello"
    var hit = 0
    switch v
    {
        case "hello", "world":
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = 2
    var hit = 0
    switch v
    {
        case 1 to 3:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = 2
    var hit = 0
    #[Swag.Complete]
    switch v
    {
        case 1 to 3:
            hit = 1
            break
    }
    @assert(hit == 1)
}

func toto()->s32 => 1
#test
{
    var hit = 0
    #[Swag.Complete]
    switch toto()
    {
        case 1 to 3:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a = 2
    var b = 1
    var hit = 0
    switch a
    {
    case 1 where b == 1:
        hit = 1
        break
    case 1 where b == 2:
        hit = 2
        break
    case 1:
        hit = 3
        break
    }
    @assert(hit == 0)
}
