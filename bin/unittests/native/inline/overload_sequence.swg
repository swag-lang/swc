#global private

func chooseOverload(value: s32 = 6)->s32 => value
func chooseOverload(left: s32, right: s32)->s32 => right

// Automatic inlining clones this body after its constant calls have been folded.
// The cloned names must keep both overloads when no selected call symbol remains.
func checkOverloadSequence()
{
    Swag.assert(chooseOverload() == 6)
    Swag.assert(chooseOverload(5) == 5)
    Swag.assert(chooseOverload(5, 7) == 7)
}

#test
{
    checkOverloadSequence()
    Swag.assert(chooseOverload(5, 7) == 7)
}
