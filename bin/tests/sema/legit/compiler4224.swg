#global fileprivate // swc-option sema-only
#global skip
struct Err {}

func titi() throw { throw Err{}; }

#[Swag.Inline]
func toto() throw => titi()

#[Swag.Optimize(.All, false)]
#test
{
    catch toto()
    @assert(@err == Err)
}
