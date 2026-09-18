using Core, Gui

// Shared field typography and help spacing for the main cards and their modal forms.
struct VaultForm {}

impl VaultForm
{
    // Returns the form options every vault form shares, measured against the theme of `wnd`.
    func options(wnd: *Wnd)->FormLayoutOptions
    {
        let gap = wnd.themeMetrics().dialog_BtnPadding
        with var result: retval
        {
            .labelHeight  = 18
            .labelSpacing = gap * 0.75
            .rowSpacing   = gap * 2
            .helpSpacing  = gap
            .labelFont    = wnd.theme().createDefaultFont(12, .Bold)
            .labelFlags   = .SecondaryText
        }

        return result
    }

    // Gives `form` the shared options before its rows are added.
    func configure(form: *FormLayoutCtrl)
    {
        form.options = options(form)
    }

    // Spaces the help paragraphs of `form` and lays it out again, once its rows are all present.
    func finish(form: *FormLayoutCtrl)
    {
        for row in form.rows where row.help != null do
            row.help.setLineGap(cast(s32) (form.themeMetrics().dialog_BtnPadding / 2))
        form.computeLayout()
        form.invalidateLayout()
    }
}
