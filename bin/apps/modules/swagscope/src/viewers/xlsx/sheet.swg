#global internal
#global namespace Viewers.Xlsx

using Core

// One independently readable worksheet; hidden sheets require an explicit reader choice.
struct Sheet
{
    name:           String
    html:           String
    cells:          u64
    omittedFormats: u64
    hidden:         bool
}

impl Sheet
{
    mtd const details()->String
    {
        var result = Format.toString(.cells == 1 ? texts().ui_Cell : texts().ui_Cells, .name, .cells)
        if .omittedFormats do
            result += Format.toString(texts().ui_FormatsOmitted, .omittedFormats)
        return result
    }
}
