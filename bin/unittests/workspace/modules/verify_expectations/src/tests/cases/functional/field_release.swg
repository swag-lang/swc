#global if #command == Swag.CompilerCommand.Test
#global private

using Core, StaticApi

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafReleaseField(node)
    let pointer = node.data
    let value = pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    node.other = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafReleaseField(node)
    let value = node.other[]
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var pointer = cast(*s32, Memory.alloc(#sizeof(s32)))
    let copy = pointer
    depUafReleaseIndirect(&pointer)
    let value = copy[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    let pointer = node.data
    depUafReleaseField(node)
    let value = pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafReplaceField(node)
    let pointer = node.data
    let value = pointer[]
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    let pointer = node.data
    depUafReplaceField(node)
    let value = pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}
