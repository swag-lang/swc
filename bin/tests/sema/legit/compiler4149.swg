#global fileprivate // swc-option sema-only
#global skip
#global #[Swag.Warning("Wrn0006", Swag.WarningLevel.Error)]
#test
{
    var x: func||(y: s32)
    x = func||(y) {}

    x(10)
}
