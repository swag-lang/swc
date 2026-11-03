#global private

struct Element
{
    value: s32    = 42
    label: string = "default"
}

var elements: [2] Element

#test
{
    for element in elements
    {
        Swag.require(element.value == 42)
        Swag.require(element.label == "default")
    }
}
