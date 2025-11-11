func toto() {}
func toto() => 0
func(T) toto() => 0
func(T) toto(a, b: s32) => 0
func(T) toto(a, b: ...) => 0
func(T, const N: s32) toto(a, b: bool...) => 0
func(T, N: s32) toto(a, b: bool...) => 0