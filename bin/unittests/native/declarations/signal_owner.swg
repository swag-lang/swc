#global private

// '#[Swag.Signal]': a callback connected through 'owner.field' receives that owner with its own
// type, whatever the callback type declares.

#[Swag.Signal]
struct(T) OwnerSignal
{
    first, second, third: T?
}

impl OwnerSignal
{
    mtd(op: Swag.Operator) opAssign(fn: T)
    {
        #assert(op == .AddAssign)
        .add(fn)
    }

    mtd add(fn: T)
    {
        if not .first do
            .first = fn
        elif not .second do
            .second = fn
        else do
            .third = fn
    }
}

struct SignalWnd
{
    id:         s32
    sigPressed: OwnerSignal'func||(*SignalWnd)
}

impl SignalWnd
{
    mtd press()
    {
        if .sigPressed.first do
            .sigPressed.first(me)
        if .sigPressed.second do
            .sigPressed.second(me)
        if .sigPressed.third do
            .sigPressed.third(me)
    }
}

struct SignalQuickButton
{
    using wnd: SignalWnd
    quick:     s32 = 7
}

func signalCountAny(wnd: *SignalWnd)
{
    wnd.id += 100
}

var g_SignalQuick: SignalQuickButton
var g_SignalSeen:  s32

#test
{
    g_SignalQuick.sigPressed += func(button) { g_SignalSeen = button.quick }
    g_SignalQuick.sigPressed.add(func(button) { g_SignalSeen += button.quick })
    g_SignalQuick.sigPressed += &signalCountAny
    g_SignalQuick.press()
    Swag.assert(g_SignalSeen == 14)
    Swag.assert(g_SignalQuick.id == 100)
}
