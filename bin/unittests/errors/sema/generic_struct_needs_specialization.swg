#global private

// A generic struct is a family of types. A value needs one of its specializations, and a
// specialization written in the source names what it lacks or what it has too many of.

struct(var T) GenericFamilyBox
{
    value: T
}

struct(var T, var U) GenericFamilyPair
{
    first:  T
    second: U
}

struct(var T = s32) GenericFamilyDefault
{
    value: T
}

struct GenericFamilyHolder
{
    box: GenericFamilyBox     // swc-expected-error {{generic struct 'GenericFamilyBox' needs generic arguments to be the type of a value}}
}

func genericFamilyBare()
{
    var box: GenericFamilyBox     // swc-expected-error {{generic struct 'GenericFamilyBox' needs generic arguments to be the type of a value}}
    discard box
}

func genericFamilyMissing()
{
    var pair: GenericFamilyPair'(s32)     // swc-expected-error {{generic struct 'GenericFamilyPair' needs a generic argument for 'U'}}
    discard pair
}

func genericFamilyTooMany()
{
    var box: GenericFamilyBox'(s32, bool)     // swc-expected-error {{generic struct 'GenericFamilyBox' accepts 1 generic argument, found 2}}
    discard box
}

func genericFamilyDefault()->s32
{
    var value: GenericFamilyDefault
    value.value = 3
    return value.value
}
