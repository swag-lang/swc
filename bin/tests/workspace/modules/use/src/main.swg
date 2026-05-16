using Dep

#main
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(DEP_MULTI_A == 13)
    @assert(DEP_MULTI_B == 17)
    @assert(DepTools.DEP_NAMESPACE_A == 31)
    @assert(DepTools.DEP_NAMESPACE_B == 37)
    @assert(DepTools.DEP_NAMESPACE_C == 41)
    @assert(DepTools.Deep.DEP_NAMESPACE_DEEP == 43)
    @assert(depLegacyValue() == 5)
}
