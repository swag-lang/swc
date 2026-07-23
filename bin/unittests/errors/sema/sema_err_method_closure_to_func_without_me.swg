#global private

struct CallbackDialog
{
    sigPressed: #null func||(*CallbackDialog, string)->bool
}

struct CallbackOwner
{
    accepted: bool
}

impl CallbackDialog
{
    mtd doModal()->string
    {
        if .sigPressed(me, "ok") do
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
        dlg.sigPressed = mtd|dlg|(dialog, buttonId)
        {
            .accepted = buttonId == "ok"
            return .accepted
        }

        return dlg.doModal()     // swc-expected-error {{sema_err_cannot_cast}}
    }
}

func semaTest001()
{
    var owner: CallbackOwner
    discard owner.bindAndRun()
}
