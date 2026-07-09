#global private

// Regression for the inline-receiver auto-member resolution fix (Sema.Member.Auto.cpp).
//
// An #[Inline] method whose body calls a #[Swag.Macro] with a #code argument that contains an
// auto-member access (`.count`, i.e. `me.count`). When the method is inlined, the macro is
// expanded inside it and the injected #code is re-resolved under the macro's own inline payload,
// which has no `me`; the auto-member must still resolve against the enclosing method's receiver
// (a parent inline payload). Mirrors core Array.opIndex calling Debug.safetyBoundCheck(index < .count).
//
// This is a same-Ast inline, so it exercises the fix directly. Before the fix it failed with
// "expected a value expression here" on `.count`.

enum CrossAstSafetyWhat
{
    BoundCheck
    Overflow
}

#[Swag.Macro]
func(what: CrossAstSafetyWhat) crossAstSafety(cond: #code->bool, loc = #callerlocation)
{
    if !#inject(cond) do
        @panic("cross-ast safety failed", loc)
}

#[Swag.Macro]
func crossAstBoundCheck(cond: #code->bool, loc = #callerlocation)
{
    crossAstSafety'(CrossAstSafetyWhat.BoundCheck)(cond, loc)
}

struct CrossAstVec
{
    value: u64
    count: u64
}

impl CrossAstVec
{
    #[Swag.Inline]
    mtd at(index: u64)->u64
    {
        crossAstBoundCheck(index < .count)
        return .value
    }
}

#test
{
    var v: CrossAstVec
    v.value = 7
    v.count = 5
    @assert(v.at(2) == 7)
    @assert(v.at(0) == 7)
}
