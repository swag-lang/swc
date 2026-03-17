#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 'B''rune
    switch x
    {
    case 'A''rune to 'C''rune:
        break
    default:
        @assert(false)
    }
}
