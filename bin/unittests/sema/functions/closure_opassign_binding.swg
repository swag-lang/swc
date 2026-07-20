#global private

alias OpAssignClosure = func||(s32)->s32

struct CallbackList
{
    cb: #null OpAssignClosure
}

impl CallbackList
{
    mtd(op: string) opAssign(fn: OpAssignClosure)
    {
        #assert(op == "+=")
        .cb = fn
    }
}

struct CallbackOwner
{
    callbacks: CallbackList
}

impl CallbackOwner
{
    mtd bind()
    {
        .callbacks += func||(value)
        {
            return value + 1
        }
    }
}

func semaTest001()
{
    var owner: CallbackOwner
    owner.bind()

    #assert(#typeof(owner.callbacks.cb) == #null OpAssignClosure)
}
