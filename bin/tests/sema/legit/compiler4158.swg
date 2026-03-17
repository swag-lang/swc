#global fileprivate // swc-option sema-only
#global skip
#global testwarning "Wrn0006"
#[Swag.Warning("Wrn0006", .Enable)]
func(T) toto(x: s32) {}

#test
{
    toto's32(0)
}
