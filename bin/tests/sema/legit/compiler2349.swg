#global fileprivate // swc-option sema-only
#global skip
func(T) lambdaToCallback(lambda: func(T)) {}

func toto(t: const *void) {}

#test
{
    lambdaToCallback(&toto)
}
