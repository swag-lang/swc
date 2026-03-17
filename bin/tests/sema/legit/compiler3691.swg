#global fileprivate
#global skip
alias F = func()

func toto() {}

func titi(x: F) {}

#test
{
    titi(&toto)
}
