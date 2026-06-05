#global fileprivate
using Swag

struct(T) LazySignal
{
    arr:      [..] T
    disabled: s32
}

impl LazySignal
{
    mtd call(params: ...)
    {
        if .disabled do
            return

        foreach fn in .arr
        {
            #ast
            {
                let ts = #typeof(T)
                return "fn(cast(" ++ ts.parameters[0].pointedType.fullname ++ ") params[0])"
            }
        }
    }
}

struct LazyMovie
{
    sigFrameChanged: LazySignal'func||(*LazyMovie)
}

impl LazyMovie
{
    mtd nextFrame()
    {
        .sigFrameChanged.call(me)
    }
}

#run
{
    var movie: LazyMovie
    movie.nextFrame()
}
