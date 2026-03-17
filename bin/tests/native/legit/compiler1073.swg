// 

#global fileprivate
#global skip
#test
{
    @assert(G == 100)
}

var G: s32 = undefined

#test
{
    G = 100
}

#drop
{
    @assert(G == 100)
}
