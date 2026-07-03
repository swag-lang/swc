#global private

// Regression: `is` on an interface must work for an *empty* derived struct
// (same memory layout/size as its base), mirroring Gui's DestroyEvent.

interface IEvt
{
}

struct EvtBase
{
    type:   typeinfo
    tag:    s32
}

impl IEvt for EvtBase {}

// Empty derived struct: same size as EvtBase.
struct DestroyEvt
{
    using base: EvtBase
}

impl IEvt for DestroyEvt {}

// Another empty derived struct.
struct CreateEvt
{
    using base: EvtBase
}

impl IEvt for CreateEvt {}

// Non-empty derived struct.
struct ResizeEvt
{
    using base: EvtBase
    extra:      s32
}

impl IEvt for ResizeEvt {}

func classify(evt: IEvt)->s32
{
    if evt is DestroyEvt do
        return 1
    if evt is CreateEvt do
        return 2
    if evt is ResizeEvt do
        return 3
    return 0
}

#test
{
    var d = DestroyEvt{}
    var c = CreateEvt{}
    var r = ResizeEvt{}

    @assert(classify(&d) == 1)
    @assert(classify(&c) == 2)
    @assert(classify(&r) == 3)
}
