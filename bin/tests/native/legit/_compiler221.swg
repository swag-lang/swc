// 

#global fileprivate
var v = 50

#test
{
    v = 6; v = (5 * 3) + 11;
    @assert(v == 26)
}
