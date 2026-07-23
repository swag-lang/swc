#global private
using Swag

namespace LazyWhereArrayInsert.Reflection
{
    #[ConstExpr, Inline]
    func canCopy(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.CanCopy) ? true : false
}

struct(T) Array {}

impl Array
{
    mtd add(value: T)
        where LazyWhereArrayInsert.Reflection.canCopy(T)
    {
        discard value
    }

    mtd insertAt(index: u64, value: T)
        where LazyWhereArrayInsert.Reflection.canCopy(T)
    {
        if index == 0 do
            return .add(value)
        .add(value)
    }
}

struct(T) Signal {}

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

struct(T) ReceiverList
{
    values: Array'T
}

impl ReceiverList
{
    mtd insert(value: T)
        where LazyWhereArrayInsert.Reflection.canCopy(T)
    {
        .values.insertAt(0, value)
    }
}

func semaTest001()
{
    var list: ReceiverList'Receiver
    var receiver: Receiver
    list.insert(receiver)
}
