#global private

// '#static switch #complete' selects a section like a plain '#static switch', and also
// requires the sections to cover every declared value of the enum.

enum StaticCompleteKind
{
    First
    Second
    Third
}

const StaticCompleteSelected = StaticCompleteKind.Second

#static switch #complete StaticCompleteSelected
{
case .First:
    const StaticCompleteResult = 1

case .Second:
    const StaticCompleteResult = 2

case .Third:
    const StaticCompleteResult = 3
}

#assert(StaticCompleteResult == 2)

// Several values can still share one section.
#static switch #complete StaticCompleteSelected
{
case .First, .Second:
    const StaticCompleteShared = 10

case .Third:
    const StaticCompleteShared = 20
}

#assert(StaticCompleteShared == 10)

// Without '#complete' the coverage is free, and 'default' stays available.
#static switch StaticCompleteSelected
{
case .First:
    const StaticPartialResult = 1

default:
    const StaticPartialResult = 99
}

#assert(StaticPartialResult == 99)
