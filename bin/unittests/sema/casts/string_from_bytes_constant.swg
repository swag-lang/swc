#global private

// A constant byte buffer reinterpreted as a 'string' folds to a string constant. It used to keep
// the array or slice constant under the 'string' type, so comparing it folded to false and
// lowering it into a 'string' field, as '#include' text often is, asserted in the compiler.
const Bytes: [3] u8        = [65, 66, 67]
const Text = cast(string, Bytes)
const Slice: const [..] u8 = [68, 69]

struct Named
{
    name: string
}

const Folded: Named = {name: Text}

#assert(Text == "ABC")
#assert(cast(string, Slice) == "DE")
#assert(Folded.name == "ABC")
#assert(Named{Text}.name.count == 3)
