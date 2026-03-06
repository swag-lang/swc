#global fileprivate
#global skip
#test
{
    var x = false
    var y = #ref &x
    while x
    {
        @assert(false)
    }
}
