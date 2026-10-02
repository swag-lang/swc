#global private

struct SubobjectPointerCommand
{
    id: s32
    using params: union
    {
        shader: struct{ shader: *s32? }
    }
}

var subobjectPointerGlobal = 41
var subobjectPointerSaved: *s32?

#[Swag.NoInline]
func subobjectPointerSet(shader: *s32?)
{
    subobjectPointerSaved = shader
}

#[Swag.NoInline]
func subobjectPointerExecute(cmd: SubobjectPointerCommand)
{
    let params = &cmd.shader
    subobjectPointerSet(params.shader)
}

#[Swag.NoInline]
func subobjectPointerExecuteDirect(cmd: SubobjectPointerCommand)
{
    subobjectPointerSet((&cmd.shader).shader)
}

#test
{
    var cmd: SubobjectPointerCommand
    cmd.shader.shader = &subobjectPointerGlobal
    subobjectPointerExecute(cmd)
    Swag.assert(subobjectPointerSaved == &subobjectPointerGlobal)
    subobjectPointerExecuteDirect(cmd)
    Swag.assert(subobjectPointerSaved == &subobjectPointerGlobal)
}

func subobjectPointerRejectLocal()
{
    var local = 7
    var cmd: SubobjectPointerCommand
    cmd.shader.shader = &local
    subobjectPointerExecute(cmd)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func subobjectPointerRejectLocalDirect()
{
    var local = 7
    var cmd: SubobjectPointerCommand
    cmd.shader.shader = &local
    subobjectPointerExecuteDirect(cmd)     // swc-expected-error {{sanity_err_borrow_escape}}
}
