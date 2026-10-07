#global private

struct CallbackDialog
{
    sigPressed: (func||(*CallbackDialog, string)->bool)?
}

struct CallbackOwner
{
    accepted: bool
}

impl CallbackDialog
{
    mtd doModal()->string
    {
        let cb = .sigPressed
        if cb and cb(me, "ok") do
            return "ok"
        return "cancel"
    }
}

impl CallbackOwner
{
    mtd bindAndRun()->string
    {
        var dlgStorage: CallbackDialog
        let dlg = &dlgStorage
        dlg.sigPressed = mtd|dlg|(dialog, buttonId)     // swc-expected-error {{sema_err_cannot_cast}}
        {
            discard dlg, dialog
            .accepted = buttonId == "ok"
            return .accepted
        }

        return dlg.doModal()
    }
}

func semaTest001()
{
    var owner: CallbackOwner
    discard owner.bindAndRun()
}
