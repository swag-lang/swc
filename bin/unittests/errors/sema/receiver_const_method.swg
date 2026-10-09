#global private

// A method that can change its receiver, called through a 'const' value, names the method and the
// receiver type rather than a cast the reader never wrote.

struct ReceiverCounter
{
    count: s32
}

impl ReceiverCounter
{
    mtd bump() { .count += 1 }
    mtd const current()->s32 => .count
}

func receiverConstCall(counter: const *ReceiverCounter)
{
    counter.bump()     // swc-expected-error {{'bump' needs a receiver of type '*ReceiverCounter', but it is called on 'const *ReceiverCounter'; [help] call it on a mutable value, or declare it with 'mtd const' if it does not change its receiver}}
}

func receiverConstRead(counter: const *ReceiverCounter)->s32 => counter.current()
