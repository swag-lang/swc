#global private

struct AA
{
    x: s32
}

impl AA
{
    const A = 52
}

impl AA
{
    const B = A
    #assert(B == 52)
    const C = 52
}

#assert(AA.C == 52)

#[Swag.Mixin]
func makeImplConst(name: string, value: string)
{
    #ast "const " ++ name ++ " = \"" ++ value ++ "\""
}

struct ImplGeneratedMember {}

impl ImplGeneratedMember
{
    #ast "const Direct = \"direct\""
    makeImplConst("Generated", "generated")
}

#assert(ImplGeneratedMember.Direct == "direct")
#assert(ImplGeneratedMember.Generated == "generated")

impl AA
{
    mtd toto() {}
    mtd titi(x: s32) {}
}

namespace ConvertNs
{
    interface IConvert
    {
        mtd convert()->string;
    }
}

namespace HashNs
{
    interface IHash32
    {
        mtd hash()->u32;
    }
}

struct QualifiedInterfacesA {}

impl ConvertNs.IConvert for QualifiedInterfacesA
{
    mtd impl convert()->string { return "converted" }
    func helper()->string { return "convert-helper" }
}

impl HashNs.IHash32 for QualifiedInterfacesA
{
    mtd impl hash()->u32 { return 123 }
    func helper()->u32 { return 456 }
}

func semaTest001()
{
    var value = QualifiedInterfacesA{}
    let conv  = cast(ConvertNs.IConvert) value
    let hash  = cast(HashNs.IHash32) value

    let converted = conv.convert()
    let hashValue = hash.hash()
    let helperText = QualifiedInterfacesA.IConvert.helper()
    let helperHash = QualifiedInterfacesA.IHash32.helper()
}

struct ImplPendingOverloadSet
{
    padIndex: u32
}

impl ImplPendingOverloadSet
{
    mtd setVibration(left, right: f32)->u32
    {
        return setVibration(.padIndex, left, right)
    }
}

impl ImplPendingOverloadSet
{
    func setVibration(padIndex: u32, left, right: f32)->u32
    {
        return padIndex
    }
}

func semaTest002()
{
    var pad = ImplPendingOverloadSet{}
    let value = pad.setVibration(0.0, 1.0)
}
