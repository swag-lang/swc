#global private

struct RuntimeHookProbe
{
    value: f32
}

impl RuntimeHookProbe
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd opSet(value: f32)
    {
        .value = value
    }
}

const Probe: RuntimeHookProbe = 1.0
#assert(Probe.value == 1.0)

