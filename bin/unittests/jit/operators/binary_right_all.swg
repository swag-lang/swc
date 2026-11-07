#global private

struct RightBinaryBox
{
    value: s32
}

impl RightBinaryBox
{
    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinaryRight(left: s32)->RightBinaryBox
        where op == .Add or op == .Sub or op == .Mul or op == .Div or op == .Mod or
              op == .BitAnd or op == .BitOr or op == .BitXor or op == .Shl or op == .Shr
    {
        #static switch op
        {
        case .Add:    return {value: left * 100 + 1}
        case .Sub:    return {value: left * 100 + 2}
        case .Mul:    return {value: left * 100 + 3}
        case .Div:    return {value: left * 100 + 4}
        case .Mod:    return {value: left * 100 + 5}
        case .BitAnd: return {value: left * 100 + 6}
        case .BitOr:  return {value: left * 100 + 7}
        case .BitXor: return {value: left * 100 + 8}
        case .Shl:    return {value: left * 100 + 9}
        case .Shr:    return {value: left * 100 + 10}
        }
    }
}

#test
{
    let box = RightBinaryBox{value: 0}
    Swag.require((3 + box).value == 301)
    Swag.require((3 - box).value == 302)
    Swag.require((3 * box).value == 303)
    Swag.require((3 / box).value == 304)
    Swag.require((3 % box).value == 305)
    Swag.require((3 & box).value == 306)
    Swag.require((3 | box).value == 307)
    Swag.require((3 ^ box).value == 308)
    Swag.require((3 << box).value == 309)
    Swag.require((3 >> box).value == 310)
}
