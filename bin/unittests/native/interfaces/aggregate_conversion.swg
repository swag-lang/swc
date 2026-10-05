#global private

interface IValue
{
    mtd value()->u32
}

struct Value { number: u32 }
impl IValue for Value
{
    mtd impl value()->u32 => .number
}

struct Holder
{
    item:  IValue
    count: u32
}

#[Swag.NoInline]
func read(holder: *Holder)->u32 => holder.item.value()

#test
{
    var value  = Value{37}
    var holder = Holder{item: &value}
    Swag.assert(holder.count == 0)
    Swag.assert(read(&holder) == 37)
}

#test
{
    var first  = Value{17}
    var second = Value{29}
    var holders: [2] IValue = [&first, &second]
    Swag.assert(holders[0].value() == 17)
    Swag.assert(holders[1].value() == 29)
}

#test
{
    var first  = Value{17}
    var second = Value{29}
    let holders: const [..] IValue = [&first, &second]
    Swag.assert(holders[0].value() == 17)
    Swag.assert(holders[1].value() == 29)
}

struct OptionalHolder
{
    item: IValue?
}

#test
{
    var value      = Value{43}
    var named: OptionalHolder = {item: &value}
    var positional = OptionalHolder{&value}
    Swag.assert(named.item!.value() == 43)
    Swag.assert(positional.item!.value() == 43)
}

struct BoxHolder
{
    value: any
    tail:  u32
}

struct CallbackHolder
{
    callback: func||()->u32
}

#[Swag.NoInline]
func runtimeNumber()->u32 => 51

struct MessageBase { message: string? }
struct Message { using base: MessageBase }

#test
{
    let value = Message{"nested scalar conversion"}
    Swag.assert(value.message == "nested scalar conversion")
}

// Boxing and closure construction also need more than copying the source bytes.
#test
{
    let number                = runtimeNumber()
    var holder                = BoxHolder{value: number}
    var array: [1] any        = [number]
    let slice: const [..] any = [number]
    Swag.assert(cast #assume(u32) holder.value == 51)
    Swag.assert(cast #assume(u32) array[0] == 51)
    Swag.assert(cast #assume(u32) slice[0] == 51)
    Swag.assert(holder.tail == 0)

    let callback = CallbackHolder{callback: &runtimeNumber}
    Swag.assert(callback.callback() == 51)
}
