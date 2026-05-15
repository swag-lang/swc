using Dep

#main
{
    @assert(DEP_VALUE == 7)
    @assert(DEP_PUBLIC_DEFAULT == 11)
    @assert(depLegacyValue() == 5)
}
