var answerValue: s32

#init { answerValue = 40 }
#premain { answerValue += 2 }
#drop
{
    Swag.assert(answerValue == 42)
    Swag.print("shared provider dropped\n")
}

#[Swag.NoInline]
public func answer()->s32 => answerValue

#[Swag.NoInline]
public func contextValue()->u64 => Swag.getContext().user0

#[Swag.NoInline]
public func verifyArguments(expected: const [..] string)->bool
{
    let actual = Swag.args()
    if actual.count != expected.count do
        return false
    for value, index in expected
    {
        if actual[index] != value do
            return false
    }
    return true
}
