#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel

// Keep disk timestamps out of snapshots while using the browser's localized date vocabulary.
func pinBrowserDates(browser: *FileBrowserCtrl)
{
    let now   = Time.DateTime{year: 2026, month: 11, day: 4, hour: 9, minute: 5}
    let dates = [now, Time.DateTime{year: 2026, month: 10, day: 26, hour: 21, minute: 30},
                 Time.DateTime{year: 2025, month: 2, day: 19}]
    for line, idx in browser.listCtrl.lines
    {
        let text = fileBrowserTime(dates[idx % dates.count], now)
        discard line!.setItem(1, text)
    }

    browser.fitDateColumn()
    browser.listCtrl.computeLayout()
}
