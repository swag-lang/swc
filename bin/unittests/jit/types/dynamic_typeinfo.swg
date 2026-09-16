#global private

struct ReflectedObject { value: s32 }
interface IReflectedObject { mtd read()->s32 }

#assert(s32 is const *Swag.TypeInfoNative)
#assert(not (s32 is const *Swag.TypeInfoStruct))
#assert((cast #assume(const *Swag.TypeInfoStruct) ReflectedObject).fields.count == 1)

func reflectStruct(type: typeinfo)->const *Swag.TypeInfoStruct?
{
    return cast #try(const *Swag.TypeInfoStruct) type
}

#test
{
    let info = reflectStruct(ReflectedObject)
    Swag.assert(info != null)
    Swag.assert(info.fields.count == 1)
    Swag.assert(reflectStruct(s32) == null)
    Swag.assert(reflectStruct(IReflectedObject) == null)
    Swag.assert(s32 is const *Swag.TypeInfoNative)
    Swag.assert(not (s32 is const *Swag.TypeInfoStruct))
}

#test
{
    // A public discriminator is descriptive data, not evidence of the allocation type.
    var forged         = Swag.TypeInfo{kind: .Struct}
    let root: typeinfo = &forged
    Swag.assert(reflectStruct(root) == null)
    forged.kind = .Native
    Swag.assert(not (root is Swag.TypeInfoNative))
}

#test
{
    var concrete: Swag.TypeInfoStruct
    concrete.kind = .Native
    let root: typeinfo = &concrete
    Swag.assert(reflectStruct(root) == &concrete)
    Swag.assert(not (root is Swag.TypeInfoNative))
    let absent: typeinfo? = null
    Swag.assert(not (absent is Swag.TypeInfoStruct))
}
