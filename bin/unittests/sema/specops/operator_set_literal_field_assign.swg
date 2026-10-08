#global private

// Assigning a literal initializes each of its fields, so a field converts through 'opSet' exactly
// as when the same literal initializes a variable. The assigned form used to reject the
// conversion with "cannot cast from 'string' to 'Text'".
struct Text
{
    length: u64
}

impl Text
{
    mtd opSet(value: string)
    {
        .length = value.count
    }
}

struct Holder
{
    text: Text
}

func name()->string => "dyn"

func initialized()->u64
{
    let holder: Holder = {text: name()}
    return holder.text.length
}

func assigned()->u64
{
    var holder: Holder
    holder = {text: name()}
    return holder.text.length
}
