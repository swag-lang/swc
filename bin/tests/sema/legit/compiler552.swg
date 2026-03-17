#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    let a = @alloc(10'u64 * 4)
    @free(a)
}
