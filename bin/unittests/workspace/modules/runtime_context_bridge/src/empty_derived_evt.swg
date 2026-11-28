#global public

// `is` on an interface value built in this imported module and checked in the consumer
// executable must work for an *empty* derived struct whose marker interface has no methods.

interface IDepEvt {}

struct DepEvtBase
{
    public
    {
        type: typeinfo?
        tag:  s32
    }
}

impl IDepEvt for DepEvtBase {}

struct DepDestroyEvt
{
    public using base: DepEvtBase
}

impl IDepEvt for DepDestroyEvt {}

struct DepResizeEvt
{
    public
    {
        using base: DepEvtBase
        extra:      s32
    }
}

impl IDepEvt for DepResizeEvt {}

// Cross-module type identity (typeinfo `==`, which compares the `crc`/runtimeHash
// after the pointer fast-path) must be stable across the module boundary: a typeinfo
// produced inside this module must compare equal to the consumer's view of the same
// imported type. Used to fail because runtimeHash folded in the importer-prefixed
// scoped name + per-compilation source refs.
func depTypeOfResizeEvt()->typeinfo  => #typeof(DepResizeEvt)
func depTypeOfDestroyEvt()->typeinfo => #typeof(DepDestroyEvt)

alias DepEvtCallback = func(IDepEvt)

// The interface value is constructed HERE (in the imported module), passed to the consumer.
func depDispatchEvt(cb: DepEvtCallback, kind: s32)
{
    switch kind
    {
    case 1:
        var e = DepDestroyEvt{}
        cb(&e)
    case 3:
        var e = DepResizeEvt{}
        cb(&e)
    }
}
