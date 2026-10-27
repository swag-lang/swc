#global public

// An erased method travels as a declaration of the instance this module compiled, so the
// struct it belongs to keeps its private layout.
struct DepErasedBase
{
    public id: s32
}

alias DepErasedUpdate = func||(*DepErasedBase, s32)

struct DepErasedAnimator
{
    target: *DepErasedBase?
    update: DepErasedUpdate?
}

impl DepErasedAnimator
{
    mtd(T is DepErasedBase) start(target: *T, update: func||(*T, s32))
    {
        .target = target
        .update = cast(DepErasedUpdate, update)
    }

    mtd step(value: s32)
    {
        .update!(unwrap .target, value)
    }
}
