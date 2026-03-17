#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let a = @alloc(10'u64 * 4)
    @free(a)
}
