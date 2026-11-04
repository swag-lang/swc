var answerValue: s32

#init { answerValue = 40 }
#premain { answerValue += 2 }
#drop
{
    Swag.assert(answerValue == 42)
    Swag.print("artifact provider dropped\n")
}

#[Swag.NoInline]
public func answer()->s32 => answerValue
