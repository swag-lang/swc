#global private

// 'Swag.AttrUsage' names the declaration kinds an attribute accepts. Writing the attribute
// directly on another kind is an error; a block still broadcasts to what it contains.

#[Swag.AttrUsage(Swag.AttributeUsage.Struct)]
attr StructOnly()

#[StructOnly]     // swc-expected-error {{sema_err_attribute_usage}}
func attrOnWrongKind()
{
}

#[Swag.EnumFlags]     // swc-expected-error {{sema_err_attribute_usage}}
func predefinedOnWrongKind()
{
}

#[Swag.Late]     // swc-expected-error {{sema_err_attribute_usage}}
func lateOnFunction()
{
}
