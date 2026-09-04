#global private

struct OrelseNonNullItem
{
    value: u32
}

#[Swag.Strict]
alias OrelseNullablePointerAlias = *OrelseNonNullItem?

#[Swag.Strict]
alias OrelseNullableStringAlias  = string?

#[Swag.Strict]
alias OrelseRequiredPointerAlias = *OrelseNonNullItem

const NullablePresentType:  typeinfo? = s32
const NullableMissingType:  typeinfo? = null
const RequiredFallbackType: typeinfo  = u64
const FoldedPresentType               = NullablePresentType orelse RequiredFallbackType
const FoldedFallbackType              = NullableMissingType orelse RequiredFallbackType

#assert(#typeof(FoldedPresentType) == typeinfo)
#assert(#typeof(FoldedFallbackType) == typeinfo)
#assert(FoldedPresentType == s32)
#assert(FoldedFallbackType == u64)

func checkValuePointerTypes(nullable: *OrelseNonNullItem?, fallback: *OrelseNonNullItem, required: *OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable
    let nullResult     = nullable orelse null

    #assert(#typeof(legacyResult) == *OrelseNonNullItem)
    #assert(#typeof(requiredResult) == *OrelseNonNullItem)
    #assert(#typeof(nullableResult) == *OrelseNonNullItem?)
    #assert(#typeof(nullResult) == *OrelseNonNullItem?)
}

func checkBlockPointerTypes(nullable: [*] OrelseNonNullItem?, fallback: [*] OrelseNonNullItem, required: [*] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [*] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == [*] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == [*] OrelseNonNullItem?)
}

func checkSliceTypes(nullable: [..] OrelseNonNullItem?, fallback: [..] OrelseNonNullItem, required: [..] OrelseNonNullItem)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == [..] OrelseNonNullItem)
    #assert(#typeof(requiredResult) == [..] OrelseNonNullItem)
    #assert(#typeof(nullableResult) == [..] OrelseNonNullItem?)
}

func checkStringTypes(nullable: string?, fallback: string, required: string)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == string)
    #assert(#typeof(requiredResult) == string)
    #assert(#typeof(nullableResult) == string?)
}

func checkCStringTypes(nullable: cstring?, fallback: cstring, required: cstring)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == cstring)
    #assert(#typeof(requiredResult) == cstring)
    #assert(#typeof(nullableResult) == cstring?)
}

func checkAnyTypes(nullable: any?, fallback: any, required: any)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == any)
    #assert(#typeof(requiredResult) == any)
    #assert(#typeof(nullableResult) == any?)
}

func checkTypeInfoTypes(nullable: typeinfo?, fallback: typeinfo, required: typeinfo)
{
    let legacyResult   = nullable orelse fallback
    let requiredResult = nullable orelse required
    let nullableResult = nullable orelse nullable

    #assert(#typeof(legacyResult) == typeinfo)
    #assert(#typeof(requiredResult) == typeinfo)
    #assert(#typeof(nullableResult) == typeinfo?)
}

func checkAliasOrelseTypes(nullablePointer: OrelseNullablePointerAlias, requiredPointer: *OrelseNonNullItem, nullableText: OrelseNullableStringAlias, requiredText: string)
{
    let requiredPointerResult = nullablePointer orelse requiredPointer
    let requiredTextResult    = nullableText orelse requiredText

    #assert(#typeof(requiredPointerResult) == *OrelseNonNullItem)
    #assert(#typeof(requiredTextResult) == string)
}

func checkConditionalNullabilityJoin(flag: bool, legacy: *OrelseNonNullItem, nullable: *OrelseNonNullItem?, required: *OrelseNonNullItem, aliasNullable: OrelseNullablePointerAlias, aliasRequired: OrelseRequiredPointerAlias)
{
    let legacyFirst            = flag ? legacy : required
    let legacySecond           = flag ? required : legacy
    let nullableFirst          = flag ? nullable : required
    let nullableLast           = flag ? required : nullable
    let nullFirst              = flag ? null : required
    let nullLast               = flag ? required : null
    let requiredOnly           = flag ? required : required
    let aliasNullableFirst     = flag ? aliasNullable : required
    let aliasNullableLast      = flag ? required : aliasNullable
    let nullAliasRequiredFirst = flag ? null : aliasRequired
    let nullAliasRequiredLast  = flag ? aliasRequired : null

    #assert(#typeof(legacyFirst) == *OrelseNonNullItem)
    #assert(#typeof(legacySecond) == *OrelseNonNullItem)
    #assert(#typeof(nullableFirst) == *OrelseNonNullItem?)
    #assert(#typeof(nullableLast) == *OrelseNonNullItem?)
    #assert(#typeof(nullFirst) == *OrelseNonNullItem?)
    #assert(#typeof(nullLast) == *OrelseNonNullItem?)
    #assert(#typeof(requiredOnly) == *OrelseNonNullItem)
    #assert(#typeof(aliasNullableFirst) == OrelseNullablePointerAlias)
    #assert(#typeof(aliasNullableLast) == OrelseNullablePointerAlias)
    #assert(#typeof(nullAliasRequiredFirst) == *OrelseNonNullItem?)
    #assert(#typeof(nullAliasRequiredLast) == *OrelseNonNullItem?)
}
