#global private

enum Shape: u8
{
    Rock     = 1
    Paper    = 2
    Scissors = 3
}

interface IShapePicker
{
    mtd pick(opponent: Shape)->Shape;
}

struct Picker {}

func choose(opponent: Shape)->Shape
{
    switch opponent
    {
    case Rock1:     // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
        return .Paper

    case .Paper:
        return .Scissors

    case .Scissors:
        return .Rock
    }

    @assert(false)
    return .Rock
}

func useDirect(opponent: Shape)->Shape
{
    return choose(opponent)
}

impl IShapePicker for Picker
{
    mtd impl pick(opponent: Shape)->Shape
    {
        return choose(opponent)
    }
}

func useInterface(opponent: Shape)->Shape
{
    var picker: Picker
    let iface = cast(IShapePicker) picker
    return iface.pick(opponent)
}

const DirectResult    = #run useDirect(.Rock)
const InterfaceResult = #run useInterface(.Rock)

// Every argument of a typed variadic attribute resolves against the parameter's enum, so a
// misspelled member is reported instead of being taken for an untyped value.
struct CommutativeBox
{
    value: s32
}

impl CommutativeBox
{
    #[Swag.Commutative(.Add, .Muul)]     // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->CommutativeBox
    {
        #if op == .Add do
            return CommutativeBox{.value + scalar}
        #else do
            #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
    }
}
