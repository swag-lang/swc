#global private

struct NarrowLoopOwner
{
    value: s32
}

func narrowLoopUse(_: *s32, _: *s32) {}

impl NarrowLoopOwner
{
    mtd keepImmutableLocal(arg: *s32?)
    {
        let font = arg
        if not font do
            return

        for row in 1
        {
            var column = row
            while column < 2
            {
                narrowLoopUse(&.value, font)
                column += 1
            }
        }
    }
}
