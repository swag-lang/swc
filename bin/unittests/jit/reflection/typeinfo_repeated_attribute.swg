#global private

#[Swag.AttrMulti]
attr Label(value: s32)

#[Label(1), Label(2)]
#[Label(3)]
struct Labeled {}

const LabeledInfo = cast(const *Swag.TypeInfoStruct, #typeof(Labeled))

#test
{
    let attributes = LabeledInfo.attributes
    Swag.require(attributes.count == 3)
    Swag.require(assume cast(s32, attributes[0].params[0].value) == 1)
    Swag.require(assume cast(s32, attributes[1].params[0].value) == 2)
    Swag.require(assume cast(s32, attributes[2].params[0].value) == 3)
}
