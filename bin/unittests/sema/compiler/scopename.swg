#global private

#assert(#typeof(#module) == string)
#assert(#module == "Sema")

struct ScopeNameOwner {}

#[Swag.Mixin]
func assertScopedValue(name: string, expectedScope: string)
{
    #assert(#scopename == expectedScope)
    #ast "#assert(\"" ++ #scopename ++ "." ++ name ++ "\" == \"" ++ expectedScope ++ "." ++ name ++ "\")"
}

impl ScopeNameOwner
{
    assertScopedValue("Generated", "ScopeNameOwner")
}
