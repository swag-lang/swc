#global private
using Swag

attr StoredTypeAttr(t: typeinfo)

const STORED_LITERAL_TYPE = #typeof([1, 2.5])

#[StoredTypeAttr(STORED_LITERAL_TYPE)]
func reflectedStoredTypeFunc()
{
}

const REFLECTED_STORED_TYPE_INFO = cast(const *TypeInfoFunc) #typeof(reflectedStoredTypeFunc)

#test
{
    func attributeStoredTypeArgument()->bool
    {
        let attribute = REFLECTED_STORED_TYPE_INFO.attributes[0]
        let value = cast(#null typeinfo) attribute.params[0].value
        return value == #type const [2] f32
    }

    const V = #run attributeStoredTypeArgument()
    #assert(V)
}
