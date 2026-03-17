#global fileprivate // swc-option sema-only
#global skip
func titi(line: string = #callerfunction)
{
    @assert(line == "__compiler1128.tata")
}

func tata()
{
    titi()
}

#test
{
    tata()
}
