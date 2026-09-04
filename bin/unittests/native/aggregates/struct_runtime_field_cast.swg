struct RuntimeText
{
    length: u64
    first:  u8
}

impl RuntimeText
{
    #[Implicit]
    mtd opSet(value: string)
    {
        .length = value.count
        .first  = .length ? value[0] : 0
    }
}

struct RuntimeChoice
{
    text: RuntimeText
    id:   string? = null
}

struct RuntimeNode
{
    marker: u64
}

func runtimeChoiceScore(choice: RuntimeChoice)->u64
{
    return choice.text.length + choice.text.first + choice.id.count
}

func runtimeResolved(parent: *RuntimeNode)->{parent: *RuntimeNode, name: RuntimeText}
{
    return {parent, "vault"}
}

// A field conversion implemented by a runtime special operator prevents the
// enclosing aggregate literal from being folded as a static struct constant.
#test
{
    Swag.assert(runtimeChoiceScore({"MiB", "mib"}) == 83)
}

// A returned aggregate can be destructured after one of its fields was built
// by a runtime special operator.
#test
{
    var node           = RuntimeNode{marker: 42}
    let {parent, name} = runtimeResolved(&node)
    Swag.assert(parent == &node)
    Swag.assert(parent.marker == 42)
    Swag.assert(name.length == 5)
    Swag.assert(name.first == 'v')
}

// Fixed-array literals use the same runtime element conversion path.
#test
{
    var values: [2] RuntimeText = ["one", "four"]
    Swag.assert(values[0].length == 3 and values[0].first == 'o')
    Swag.assert(values[1].length == 4 and values[1].first == 'f')
}
