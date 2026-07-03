#global private

struct(T) Signal
{
}

impl Signal
{
    mtd call(params: ...)
    {
        var fn: T

        #ast
        {
            let ts = #typeof(T)
            return "fn(cast(" ++ ts.parameters[0].pointedType.fullname ++ ") params[0])\n"
        }
    }
}

struct Receiver
{
    signal: Signal'func||(*Receiver)
}

func semaTest001()
{
    var receiver: Receiver
    receiver.signal.call(null)
}
