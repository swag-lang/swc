using Dep

#main
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(DEP_MULTI_A == 13)
    @assert(DEP_MULTI_B == 17)
    @assert(depLegacyValue() == 5)
}
