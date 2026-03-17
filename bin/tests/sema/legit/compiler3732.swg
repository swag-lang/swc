#global fileprivate // swc-option sema-only
#global skip
/* salut la foule
		/* */
	*/

var G = 0
#premain
{
    G += 1
}

#init
{
}

#test
{
    @assert(G == 1)
}
