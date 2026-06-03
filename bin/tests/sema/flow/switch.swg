#global fileprivate

func semaTest001()
{
    var v = 2
    switch v
    {
        case 1:
            break
        case 2, 3:
            break
        default:
            break
    }
}

func semaTest002()
{
    switch 1
    {
        case 1:
            break
        default:
            break
    }

    switch 1
    {
        case 1:
            break
        default:
            break
    }
}

func semaTest003()
{
    alias MyInt = s32
    var v : MyInt = 3
    switch v
    {
        case 1:
            break
        case 3:
            break
        default:
            break
    }
}

func semaTest004()
{
    var v = 1.5
    switch v
    {
        case 1.5:
            break
        default:
            break
    }
}

func semaTest005()
{
    var v = true
    switch v
    {
        case true:
            break
        default:
            break
    }
}

func semaTest006()
{
    var v = "hello"
    switch v
    {
        case "hello", "world":
            break
        default:
            break
    }
}

func semaTest007()
{
    var v = 2
    switch v
    {
        case 1 to 3:
            break
        default:
            break
    }
}

func semaTest008()
{
    var v = 2
    #[Swag.Complete]
    switch v
    {
        case 1 to 3:
            break
    }
}

func toto()->s32 => 1
func semaTest009()
{
    #[Swag.Complete]
    switch toto()
    {
        case 1 to 3:
            break
    }
}

func semaTestContinueFromSwitchCaseInLoop()
{
    var total: s32 = 0
    for i in 1 to 5
    {
        switch i
        {
            case 2, 4:
                continue
        }
        total += cast(s32) i
    }
}

func semaTest010()
{
    var a = 2
    var b = 1
    switch a
    {
    case 1 where b == 1:
        break
    case 1 where b == 2:
        break
    case 1:
        break
    }
}

func semaTest011()
{
    var hit = 0
    switch 1
    {
        case 1: hit += 1; hit += 2
        default:
            break
    }

    #assert(#typeof(hit) == s32)
}

func semaTest012()
{
    var c = '{'
    var garbage, group, score, count = 0
    switch
    {
        case c == '!' and garbage:
            count += 10
        case c == '>' and garbage:
            garbage -= 1
        case c == '<' and !garbage:
            garbage += 1
        case c == '{' and !garbage:
            group += 1; score += group
        case c == '}' and !garbage:
            group -= 1
        case garbage:
            count += 1
        default:
            break
    }

    #assert(#typeof(score) == s32)
}
