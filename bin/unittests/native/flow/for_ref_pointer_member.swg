#global private

struct RefPointerOperation
{
    started: bool
}

struct RefPointerPreview
{
    using operation: RefPointerOperation
}

#test
{
    var preview = RefPointerPreview{operation: {started: true}}
    var previews: [1] *RefPointerPreview = [&preview]
    var count = 0
    for &entry in previews
    {
        if entry[].started do
            count += 1
    }
    Swag.require(count == 1)
}
