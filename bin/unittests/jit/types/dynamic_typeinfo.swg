#global private

struct ReflectedObject { value: s32 }
interface IReflectedObject { mtd read()->s32 }

#assert(s32 is const *Swag.TypeInfoNative)
#assert(not (s32 is const *Swag.TypeInfoStruct))
#assert(assume cast(const *Swag.TypeInfoStruct, ReflectedObject).fields.count == 1)

func reflectStruct(type: typeinfo)->const *Swag.TypeInfoStruct?
{
    return (catch cast(const *Swag.TypeInfoStruct?, type))
}

#test
{
    let info = reflectStruct(ReflectedObject)
    Swag.require(info != null)
    Swag.require(info.fields.count == 1)
    Swag.require(reflectStruct(s32) == null)
    Swag.require(reflectStruct(IReflectedObject) == null)
    Swag.require(s32 is const *Swag.TypeInfoNative)
    Swag.require(not (s32 is const *Swag.TypeInfoStruct))
}

#test
{
    // A public discriminator is descriptive data, not evidence of the allocation type.
    var forged         = Swag.TypeInfo{kind: .Struct}
    let root: typeinfo = &forged
    Swag.require(reflectStruct(root) == null)
    forged.kind = .Native
    Swag.require(not (root is Swag.TypeInfoNative))
}

#test
{
    var concrete: Swag.TypeInfoStruct
    concrete.kind = .Native
    let root: typeinfo = &concrete
    Swag.require(reflectStruct(root) == &concrete)
    Swag.require(not (root is Swag.TypeInfoNative))
    let absent: typeinfo? = null
    Swag.require(not (absent is Swag.TypeInfoStruct))
}
