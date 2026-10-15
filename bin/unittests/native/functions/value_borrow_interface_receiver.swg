#global private
#global #[Swag.Safety(.ValueBorrow, true)]

// An interface call passes its receiver object before the declared parameters. Taking that
// receiver for the first parameter borrowed the temporary interface value with the size of the
// argument, which covered the call's own result slot.

struct Big { values: [64] u64 }
struct Made { handle, width, height: u64 }
struct Holder { big: Big }

interface IMaker
{
    mtd make(value: Big)->Made
}

struct Maker { next: u64 }

impl Maker
{
    #[Swag.NoInline]
    mtd makeImpl(value: const *Big)->Made
    {
        var result: retval
        result.handle = .next + value.values[0]
        .next         += 1
        return result
    }
}

impl IMaker for Maker
{
    mtd impl make(value: Big)->Made => .makeImpl(&value)
}

var g_Maker: Maker

#[Swag.NoInline]
func maker()->IMaker => &g_Maker

#[Swag.NoInline]
func makeFromTemporaryReceiver(holder: const *Holder)->u64
{
    let made = maker().make(holder.big)
    return made.handle
}

#test
{
    var holder: Holder
    holder.big.values[0] = 5
    Swag.assert(makeFromTemporaryReceiver(&holder) == 5)
}
