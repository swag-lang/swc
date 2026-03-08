#global fileprivate

func toto()->bool { return true; }
func toto1()->bool { return true; }

#run
{
    @assert(toto() == toto1())
}
