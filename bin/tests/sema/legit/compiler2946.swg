#global fileprivate // swc-option sema-only
#global skip
struct BaseRenderOgl {}

struct RenderOgl
{
    using base: BaseRenderOgl
}

impl BaseRenderOgl
{
    func toto(me) {}
}

#test
{
    var render: RenderOgl
    render.base.toto()
}
