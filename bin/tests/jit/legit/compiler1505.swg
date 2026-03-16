#global fileprivate // swc-option suite-jit
#global skip
#[Swag.Compiler]
func set(x: string)
{
    @assert(x == "inside function set")
    //@print(x)
}

//#[Swag.PrintBc]
#test
{
    #run
    {
        let x = "inside function set"
        set(x)
    }
}
