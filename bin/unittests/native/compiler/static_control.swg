#global if true
#global private

const UsePrimary = false

#static if UsePrimary
{
    const SelectedIf = 1
}
elif true
{
    const SelectedIf = 2
}
else
{
    #error("unreachable static else branch")
}

enum StaticMode
{
    First
    Second
}

const SelectedMode = StaticMode.Second

#static switch SelectedMode
{
case .First:
    #error("unreachable static switch case")

case .Second:
    const SelectedSwitch = 40

default:
    #error("unreachable static switch default")
}

struct StaticFields
{
    #static switch SelectedMode
    {
    case .First:
        wrong: string

    case .Second:
        value: s32

    default:
        wrongDefault: string
    }
}

enum StaticValues
{
    #static switch SelectedMode
    {
    case .First:
        Wrong

    case .Second:
        Value0
        Value1

    default:
        WrongDefault
    }
}

func selectedInFunction()->s32
{
    #static switch 2
    {
    case 1:
        #error("unreachable function case")

    case 2:
        return SelectedIf + SelectedSwitch

    default:
        #error("unreachable function default")
    }
}

func selectedFromMultipleCases()->s32
{
    #static switch SelectedMode
    {
    case .First, .Second:
        return 42
    }
}

func(T) selectedFromType()->s32
{
    #static switch T
    {
    case s32:
        return 42

    default:
        #error("unreachable generic type default")
    }
}

#test
{
    let value = StaticFields{2}
    Swag.assert(value.value == 2)
    Swag.assert(StaticValues.Value0 != StaticValues.Value1)
    Swag.assert(selectedInFunction() == 42)
    Swag.assert(selectedFromMultipleCases() == 42)
    Swag.assert(selectedFromType's32() == 42)
}
