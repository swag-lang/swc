#global private

struct CatchNarrowHolder
{
    value: *s32?
}

func catchNarrowValue()->s32 fail => 1
func catchNarrowUse(_: *s32) {}

func catchReturningHandler(holder: *CatchNarrowHolder)
{
    let first = catch catchNarrowValue()
    {
        catchNarrowUse(unwrap holder.value)
        return
    }

    let second = catch catchNarrowValue()
    {
        catchNarrowUse(unwrap holder.value)
        return
    }

    discard first, second
}

func catchContinuingHandler(holder: *CatchNarrowHolder)
{
    discard catch catchNarrowValue()
    {
        catchNarrowUse(unwrap holder.value)
    }

    discard catch catchNarrowValue()
    {
        catchNarrowUse(unwrap holder.value)
    }
}

func catchKeepsEarlierProof(holder: *CatchNarrowHolder)
{
    if not holder.value do return

    discard catch catchNarrowValue()
    {
        catchNarrowUse(holder.value)
    }

    catchNarrowUse(holder.value)
}
