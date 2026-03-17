#global fileprivate // swc-option sema-only
#global skip
struct Err {}

func toto() throw
{
    throw Err{}
}

#test
{
    catch toto()
    @assert(@err == Err)
}
