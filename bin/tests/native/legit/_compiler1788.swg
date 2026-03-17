// 

#global fileprivate
 
//#[Swag.PrintBc]
#test
{
    G += 1
    @assert(G == 1)
}

//#[Swag.PrintBc]
#init
{
    //@assert(G == 1)
}

var G: s64
