#global private

// Self-borrows need no annotation. They are valid locally, but copying the
// carrier out of the frame does not relocate the storage its fields address.
struct SelfStorage
{
    values: [4] s32
    cursor: *s32?
}

func returnSelfStorage()->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[0]
    return source     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnSelfStoragePointer()->*s32?
{
    var source = SelfStorage{}
    source.cursor = &source.values[1]
    return source.cursor     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnCopiedSelfStorage()->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[2]
    let copy = source
    return copy     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnReboundSelfStorage(pointer: *s32)->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[0]
    source.cursor = pointer
    return source
}

struct SelfSlice
{
    values: [4] s32
    view:   [..] s32
}

func returnSelfSlice()->SelfSlice
{
    var source: SelfSlice
    source.values = [0, 0, 0, 0]
    source.view   = source.values
    return source     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct NestedSelfStorage
{
    item: SelfStorage
}

func returnNestedSelfStorage()->NestedSelfStorage
{
    var source = NestedSelfStorage{}
    source.item.cursor = &source.item.values[0]
    return source     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnClearedSelfStorage()->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[0]
    source.cursor = null
    return source
}

func returnConditionallyClearedSelfStorage(clear: bool)->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[0]
    if clear do source.cursor = null
    return source     // swc-expected-error {{sanity_err_borrow_escape}}
}

func returnFullyReboundSelfStorage(pointer: *s32, clear: bool)->SelfStorage
{
    var source = SelfStorage{}
    source.cursor = &source.values[0]
    if clear do source.cursor = null
    else do source.cursor = pointer
    return source
}

#test
{
    var source = SelfStorage{}
    source.cursor   = &source.values[0]
    source.cursor[] = 7
    let copy = source
    Swag.assert(source.values[0] == 7)
    Swag.assert(copy.cursor![] == 7)

    var external = 9
    let rebound  = returnReboundSelfStorage(&external)
    Swag.assert(rebound.cursor![] == 9)
    Swag.assert(returnClearedSelfStorage().cursor == null)
    Swag.assert(returnFullyReboundSelfStorage(&external, true).cursor == null)
    let branchRebound = returnFullyReboundSelfStorage(&external, false)
    Swag.assert(branchRebound.cursor![] == 9)
}
