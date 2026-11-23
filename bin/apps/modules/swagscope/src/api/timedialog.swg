#global public
#global namespace Viewer

using Core, Gui

// Opens a time address for editing. Relative jumps use the position at the time the sheet opened.
// The reader supplies localized wording and receives the validated destination in seconds.
func(T) createTimeDialog(view: *T, origin, duration: f64, title, help, error, confirm: string, seek: func(*T, f64))->*EditDlg
{
    let initial = timeText(origin)
    with var options: EditDlgOptions
    {
        .title             = title
        .message           = help
        .text              = initial
        .confirmButtonText = confirm
    }

    let dialog = EditDlg.createSingleLine(unwrap view.surface, options)
    dialog.edit!.setValidator(func|origin, duration, dialog, help, error|(edit: *EditBox)->EditBoxCheckResult
    {
        let valid = parseTimeAddress(edit.text(), origin, duration) >= 0
        dialog.setMessage(valid ? help : error)
        return valid ? .Valid : .InvalidVisible
    })
    dialog.validateResult = func|view, dialog, origin, duration, seek|(_, result)->bool
    {
        if result != Dialog.BtnOk do
            return true
        let target = parseTimeAddress(dialog.text(), origin, duration)
        if target < 0
        {
            discard dialog.edit!.revalidate()
            return false
        }

        seek(view, target)
        return true
    }
    return dialog
}
