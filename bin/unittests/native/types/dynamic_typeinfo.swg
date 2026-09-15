#global private

struct ReflectedObject { value: s32 }
interface IReflectedObject { mtd read()->s32 }

#assert(cast #try(const *Swag.TypeInfoNative) s32 != null)
#assert(cast #try(const *Swag.TypeInfoStruct) s32 == null)
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
    Swag.assert(cast #try(const *Swag.TypeInfoNative) s32 != null)
    Swag.assert(cast #try(const *Swag.TypeInfoStruct) s32 == null)
}

#test
{
    // A public discriminator is descriptive data, not evidence of the allocation type.
    var forged         = Swag.TypeInfo{kind: .Struct}
    let root: typeinfo = &forged
    Swag.assert(reflectStruct(root) == null)
    forged.kind = .Native
    Swag.assert(cast #try(const *Swag.TypeInfoNative) root == null)
}

#test
{
    var concrete: Swag.TypeInfoStruct
    concrete.kind = .Native
    let root: typeinfo = &concrete
    Swag.assert(reflectStruct(root) == &concrete)
    Swag.assert(cast #try(const *Swag.TypeInfoNative) root == null)
    let absent: typeinfo? = null
    Swag.assert(cast #try(const *Swag.TypeInfoStruct) absent == null)
}
