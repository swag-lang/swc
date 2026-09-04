#global public

alias DepCount = s32

#[Swag.NoDuplicate]
enum DepMode: s16
{
    Zero = 0
    Big  = 42
}

struct DepPair
{
    public
    {
        left:  DepCount
        right: s32
    }
}

struct DepShortCallTarget {}

impl DepShortCallTarget
{
    mtd const ready()->bool => true
}

struct DepShortCallOwner
{
    public target: DepShortCallTarget
}

struct DepImportedDefaultInner
{
    public
    {
        minStep: f32 = 1 / 100000.0
        maxStep: f32 = 1
        seed:    s32 = 17
    }
}

struct DepImportedDefaultOuter
{
    public
    {
        required: s32
        timing:   DepImportedDefaultInner
        marker:   s32 = 42
    }
}

impl DepShortCallOwner
{
    mtd const ready()->bool => .target.ready()
}

struct DepPublicWithPrivateField
{
    public publicValue: s32
    hiddenValue:        s32
}

// A member that says nothing is internal, exactly like a top-level declaration that says
// nothing, so only 'shownValue' crosses the module boundary.
struct DepDefaultAccessField
{
    public shownValue: s32
    defaultValue:      s32
}

struct DepPublicWithPrivateInlineUnion
{
    public publicValue: s32
    using bounds:       union
    {
        signed:   { min: s32, max: s32 } = {0, 0}
        floating: { min: f32, max: f32 } = {0, 0}
    }
}

func makeDepPublicWithPrivateField(value: s32)->DepPublicWithPrivateField
{
    return {publicValue: value, hiddenValue: value + 1}
}

func makeDepDefaultAccessField(value: s32)->DepDefaultAccessField
{
    return {shownValue: value, defaultValue: value + 1}
}

struct(T) DepGenericLayout
{
    public value: T
}

union DepValue
{
    public
    {
        asInt:   s32
        asFloat: f32
    }
}

#[Swag.Opaque, Swag.Pack(8)]
struct DepOpaque
{
    public
    {
        opaqueHead: u64
        opaqueTail: u32
    }
}

#[Swag.Opaque]
struct DepOpaqueGenericBox
{
    seed: s32
}

impl DepOpaqueGenericBox
{
    mtd init(seed: s32)
    {
        .seed = seed
    }

    mtd(T) addSeed(value: T)->T
    {
        return value + cast(T) .seed
    }
}

interface IDepScore
{
    mtd score(value: s32)->s32
}

namespace DepTools
{
    struct DepNamespaced
    {
        public value: s16
    }

    interface IHash32
    {
        mtd const compute()->u32
    }

    impl IHash32 for DepNamespaced
    {
        mtd const impl compute()->u32
        {
            return cast(u32) .value + 0x100'u32
        }
    }

    #[Swag.ConstExpr]
    func(T) hash32WithGeneratedFullName(value: T)->u32
    {
        #static if #defined(T.IHash32) do
            #ast "return " ++ #typeof(T).fullname ++ ".IHash32.compute(value)"
        else do
            return 0
    }

    #[Swag.Mixin]
    func depMakeGeneratedCommandId(name: string)
    {
        #ast "const " ++ name ++ " = \"DepTools.DepGeneratedCommandOwner." ++ name ++ "\""
    }

    struct DepGeneratedCommandOwner {}

    impl DepGeneratedCommandOwner
    {
        depMakeGeneratedCommandId("GeneratedAccept")
    }
}

namespace DepSharedRng
{
    struct MWC
    {
        public value: u32 = 0x12345678
    }

    impl MWC
    {
        mtd nextU32()->u32 => .value
    }

    #[Swag.Opaque]
    struct(T = MWC) Rng
    {
        public rng: T
    }

    impl Rng
    {
        #[Inline]
        func(TA) makeScratch()->Rng'TA
        {
            var result: retval
            return result
        }

        mtd nextU32()->u32 => 0x12345678
    }

    public func shared(rng: *Rng'MWC)->*Rng'MWC => rng
}
