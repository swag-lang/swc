#global if #command == Swag.CompilerCommand.Test
#global private

struct DuplicatePlanKeys
{
    #[Serialization.Key("shared")]
    first: s32

    #[Serialization.Key("shared")]
    second: s32
}

struct EmptyPlanKey
{
    #[Serialization.Key("")]
    value: s32
}

func buildSerializationPlan(type: typeinfo) fail
{
    let structType = assume cast(const *Swag.TypeInfoStruct, type)
    discard try Serialization.planFor(structType)
}

// The captured error keeps both source field names and their conflicting wire key.
#test
{
    catch buildSerializationPlan(DuplicatePlanKeys) as error
    Swag.assert(error is Errors.SerializationError)
    let message = Errors.message(error)
    Swag.assert(Utf8.contains(message, #typeof(DuplicatePlanKeys).fullname!))
    Swag.assert(Utf8.endsWith(message, "fields [[first]] and [[second]] use key [[shared]]"))
}

#test
{
    catch buildSerializationPlan(EmptyPlanKey) as error
    Swag.assert(error is Errors.SerializationError)
    Swag.assert(Errors.message(error) == "serialized field needs a non-empty key")
}
