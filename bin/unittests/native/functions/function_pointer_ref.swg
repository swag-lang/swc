#global private

alias ReferencedFunction = func()->s32

struct ReferencedFunctionHolder
{
    callback: ReferencedFunction
}

impl ReferencedFunctionHolder
{
    mtd const atFn()->const &ReferencedFunction => &.callback
}

func referencedFunctionTarget()->s32 => 42

#test
{
    let holder: ReferencedFunctionHolder = {callback: &referencedFunctionTarget}
    let callback = holder.atFn()
    @assert(callback() == 42)
}
