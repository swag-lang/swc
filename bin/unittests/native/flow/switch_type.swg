#global private

#test
{
    var a: typeinfo = s32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    }
    @assert(hit == 1)
}

#test
{
    var a: typeinfo = s32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    }
    @assert(hit == 1)
}

#test
{
    var a: typeinfo = f32
    var hit         = 0
    switch a
    {
    case s32:
        hit = 1
        break
    default:
        hit = 2
        break
    }
    @assert(hit == 2)
}

// A nullable form is the same type as the plain one, so 'case' selects it just like '=='
// does. Each qualified form owns a distinct descriptor, so matching descriptor addresses
// instead of type identity would silently fall through to 'default'.
#test
{
    var text: #null string = "value"
    var a: typeinfo        = #typeof(text)
    @assert(a == string)

    var hit = 0
    switch a
    {
    case string:
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
    var ptr: #null *s32
    var a: typeinfo = #typeof(ptr)
    @assert(a == *s32)

    var hit = 0
    switch a
    {
    case *s32:
        hit = 1
        break
    default:
        hit = 2
        break
    }
    @assert(hit == 1)
}
