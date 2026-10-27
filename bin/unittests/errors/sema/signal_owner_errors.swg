#global private

#[Swag.Signal]
struct(T) ErrSignal
{
    first: T?
}

impl ErrSignal
{
    mtd(op: Swag.Operator) opAssign(fn: T)
    {
        #assert(op == .AddAssign)
        .first = fn
    }
}

struct ErrSignalWnd
{
    sigPressed: ErrSignal'func||(*ErrSignalWnd)
}

struct ErrQuickButton { using wnd: ErrSignalWnd; quick: s32 }
struct ErrIconButton { using wnd: ErrSignalWnd; icon: s32 }

func errOnQuick(button: *ErrQuickButton)
{
    button.quick = 0
}

var g_ErrIcon: ErrIconButton

// A callback written for another derived struct would receive the icon button.
#test
{
    g_ErrIcon.sigPressed += &errOnQuick     // swc-expected-error {{sema_err_binary_operand_type}}
}

// A signal keeps its callbacks with their owner.
#test
{
    let copy = g_ErrIcon.sigPressed     // swc-expected-error {{sema_err_cannot_copy_signal}}
}
