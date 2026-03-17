#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    {
        var x = 2.0'f32
        x = @sqrt(x)
        //@print(cast(f64) x)
    }
}
