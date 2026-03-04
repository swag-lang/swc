/*#[Swag.Compiler, Swag.Inline]
func set()
{
    @assert(@jit)
}

//#[Swag.PrintBc]
#test
{
    var x = 0
    for 10
    {
        #run
        {
            @assert(@jit)
            set()
        }

        x += 1
    }

    @assert(x == 10)
}*/
