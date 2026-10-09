#global private

// An unqualified name that nothing declares suggests the closest name the lookup could see: a
// local, a parameter, or a declaration of the file, when the spelling is near one.

struct SuggestPoint
{
    x: s32
}

func suggestType(_: SuggestPiont)->s32 => 0     // swc-expected-error {{unknown symbol 'SuggestPiont'; [help] use 'SuggestPoint' instead}}

func suggestLocal()->s32
{
    var total = 0
    for i in 0 until 10 do totl += i     // swc-expected-error {{unknown symbol 'totl'; [help] use 'total' instead}}
    return total
}

func suggestNothing()->s32 => unrelatedName     // swc-expected-error {{unknown symbol 'unrelatedName'}}

func suggestForeignType(_: int)->s32 => 0     // swc-expected-error {{unknown symbol 'int'; [help] use 's32' instead}}
