#global private

// A method that can change its receiver, called through a 'const' value, names the method and the
// receiver type rather than a cast the reader never wrote. The wording is what is checked.

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
    counter.bump()     // swc-expected-error {{'bump' needs a receiver of type '*ReceiverCounter', but it is called on 'const *ReceiverCounter'}}
}

func receiverConstRead(counter: const *ReceiverCounter)->s32 => counter.current()
