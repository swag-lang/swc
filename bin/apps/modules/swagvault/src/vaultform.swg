using Core, Gui

// Shared field typography and help spacing for the main cards and their modal forms.
struct VaultForm {}

impl VaultForm
{
    func options(wnd: *Wnd)->FormLayoutOptions
    {
        let gap = wnd.themeMetrics().dialog_BtnPadding
        var result: retval
        result.labelHeight  = 18
        result.labelSpacing = gap * 0.75
        result.rowSpacing   = gap * 2
        result.helpSpacing  = gap
        result.labelFont    = wnd.theme().createDefaultFont(12, .Bold)
        result.labelFlags   = .SecondaryText
        return result
    }

    func configure(form: *FormLayoutCtrl)
    {
        form.options = options(form)
    }

    func finish(form: *FormLayoutCtrl)
    {
        for row in form.rows where row.help != null do
            row.help.setLineGap(cast(s32) (form.themeMetrics().dialog_BtnPadding / 2))
        form.computeLayout()
        form.invalidateLayout()
    }
}
