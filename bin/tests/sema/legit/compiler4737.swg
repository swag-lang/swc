#global fileprivate
#global skip
var G = 0
func toto() { G = 1; }

alias O = toto
alias P = O

#test
{
    P()
    @assert(G == 1)
}
