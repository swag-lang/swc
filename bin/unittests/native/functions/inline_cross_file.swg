#global private

#[Swag.NoInline]
func source()->s32 => 20

#[Swag.NoInline]
func createValue(value: s32)->s32 => InlineCrossFile.Factory.create's32(value)

struct TextEvent { text: InlineCrossFile.Text }
struct TextItem { text: InlineCrossFile.TextTarget }

func assignText(item: *TextItem, event: *TextEvent)
{
    item.text = event.text
}

#test
{
    let value = source()
    Swag.assert(InlineCrossFile.nested(value) == 42)
    Swag.assert(InlineCrossFile.identity(value) == 20)
    Swag.assert(InlineCrossFile.withCallback(value) == 60)
    Swag.assert(createValue(value) == 23)
    var event = TextEvent{{"abc".buffer, 3}}
    var item: TextItem
    assignText(&item, &event)
    Swag.assert(item.text.count == 3)

    let a          = InlineCrossFile.Vector's32{value, 3}
    let b          = InlineCrossFile.Vector's32{2, 5}
    let sum        = a + b
    let difference = a - b
    Swag.assert(sum.x == 22 and sum.y == 8)
    Swag.assert(difference.x == 18 and difference.y == -2)

    var values = [10, 20, 30]
    let bias   = 2
    InlineCrossFile.forEachMutable(values, func|bias|(element: *s32) { element[] += bias })
    Swag.assert(values[0] == 12 and values[1] == 22 and values[2] == 32)
    var buffer = InlineCrossFile.Buffer's32{&values[0]}
    buffer[1] += 7
    Swag.assert(buffer[1] == 29 and values[1] == 29)
}
