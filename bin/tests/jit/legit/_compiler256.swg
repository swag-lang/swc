#global fileprivate
using Swag

#run
{
    var i = 5
    while i > 0
    {
        i -= 1; }

    @assert(i == 0)
}
