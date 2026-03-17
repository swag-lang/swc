#global fileprivate // swc-option sema-only
#global skip
struct ErrToto {}
struct ErrTiti {}

func toto() throw
{
    throw ErrToto{}
}

func titi() throw
{
    throw ErrTiti{}
}

//#[Swag.PrintBc]
//#[Swag.Optimize(.All, false)]
#test
{
    catch
    {
        toto()
        titi()
    }

    @assert(@err == ErrTiti)
}
