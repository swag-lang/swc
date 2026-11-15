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
    let oldData = node.data
    depUafInferredReleaseProjected(node)
    let value = node.data[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
    let oldValue = oldData[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard oldValue
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    let oldData = node.data
    depUafInferredReplaceWrapper(node)
    let value = node.data[]
    discard value
    let oldValue = oldData[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard oldValue
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    let oldData = node.data
    depUafInferredReplaceWrapper2(node)
    let value = node.data[]
    discard value
    let oldValue = oldData[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard oldValue
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseWrapper(node)
    let value = node.data[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let left = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    let right = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    left.padding = 0
    left.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    right.padding = 0
    right.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseSecond(left, right)
    let leftValue = left.data[]
    discard leftValue
    let rightValue = right.data[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard rightValue
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseWrapper2(node)
    let value = node.data[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredAliasReleaseField(node)
    let value = node.data[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReplaceField(node)
    let value = node.data[]
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseThenCallback(node, &depUafRefillField)
    let value = node.data[]
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseThenRefill(node)
    let value = node.data[]
    discard value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*DepUafNode, Memory.alloc(#sizeof(DepUafNode)))
    node.padding = 0
    node.data = cast(*s32, Memory.alloc(#sizeof(s32)))
    depUafInferredReleaseField(node)
    let value = node.data[]     // swc-expected-error {{sanity_err_use_after_free}}
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
