using Core, Gui

// One drive sCrypt currently exposes, and the container behind it.
struct MountedDrive
{
    volume:        #null *WinFsp.MountedVolume     // Live mount, owned by this entry until it is unmounted.
    path:          String                          // Container file the drive reads and writes.
    drive:         String                          // Drive letter Windows shows it on.
    needsPassword: bool                            // Whether a password was needed to open the container.
    readOnly:      bool                            // Whether the drive was mounted for reading alone.
    atStartup:     bool                            // Whether sCrypt mounts this container again the next time it starts.
}

// Columns of the mounted-drives list, in the order `MountedDrives.create` adds them.
//
// The first one carries no text: a list row draws its check box in its first cell, so that
// column is the check box, and the heading above it is what says what checking one means.
internal enum MountedColumn
{
    Startup     // Whether the drive comes back the next time sCrypt starts.
    Drive       // Drive letter the volume appears on.
    Vault       // Container file behind the drive.
}

// The third card of the window: the drives sCrypt currently exposes.
//
// It is the answer to "what is running", and it is a column rather than a strip under the two
// forms: drives are a list that grows, and a list grows downwards. Its shape is the shape of
// the two cards beside it, so the surface reads as three panels doing three things rather than
// as two panels and a table.
//
// Rows are the entries of `drives`, in order and never sorted, which is what lets a row index
// stand for a drive everywhere else.
struct MountedDrives
{
    card:          VaultCard   = undefined
    list:          *ListCtrl   = undefined
    empty:         *Label      = undefined
    unmountButton: *PushButton = undefined
    drives:        Array'MountedDrive

    // Emitted once the table says what `drives` now holds. Whether the action of the card can
    // work depends on the selection *and* on what the window is doing, so the window is what
    // answers for it; this is how it learns that the set changed under it.
    sigDrivesChanged: SigArray'func||(*MountedDrives)
}

impl MountedDrives
{
    // Width of the two columns whose content has a known shape. The vault name takes what they
    // leave, because it is the one column a reader actually needs wide.
    const StartupColumnWidth = 92'f32
    const DriveColumnWidth   = 78'f32
    const MinimumVaultWidth  = 120'f32

    // Side of the padlock a read-only drive carries, at the row size of the chart.
    const LockIconSize = 16'f32

    func create(parent: *Wnd)->MountedDrives
    {
        let card = VaultCard.create(parent, appStrings().ui_MountedCardTitle, appStrings().ui_MountedCardHelp)

        let unmount = PushButton.create(card.actions, appStrings().ui_Unmount, {0, 0, 0, 36})
        unmount.setIcon(card.panel.theme().icon(ThemeIcons.Stop, 18))
        card.actions.computeLayout()

        // The card carries no fields, so its form collapses to nothing and the table takes the
        // whole body. Sizing it is still the card's job, exactly as on the two form cards.
        card.endForm()

        // The table sits on the card's own fill, so it draws no ground of its own: a framed
        // list inside a raised panel is the second box the panel exists to avoid. Its heading
        // row keeps the one hairline that separates the headings from the rows.
        let list = ListCtrl.createMultiColumns(card.body)
        list.dockStyle                = .Center
        list.backgroundStyle          = .Transparent
        list.listView.backgroundStyle = .Transparent
        list.header.form              = .Transparent
        list.setSelectionMode(.Single)
        list.updateFlags(add: .HotTrack)

        // Sorting would put the rows in an order the drive list no longer matches, and a
        // handful of drives have nothing to sort anyway.
        list.header.updateFlags(remove: .Clickable)

        list.addColumn(appStrings().ui_ColStartup, StartupColumnWidth)
        list.addColumn(appStrings().ui_ColDrive, DriveColumnWidth)
        list.addColumn(appStrings().ui_ColVault, MinimumVaultWidth)

        // Only a read-only drive carries a padlock, and the lane it stands in is reserved on every
        // row whatever the state: sized to its content, the column would put the letters of two
        // drives at two different places and the reader would read the difference as a typo.
        list.setIconSize(LockIconSize)
        list.header.itemAt(cast(u32) MountedColumn.Drive).reservesIconSpace = true

        // An empty table is a card with a heading and nothing under it, which reads as a table
        // that failed to load. One quiet line says the truth instead, and steps aside the
        // moment there is a row to show.
        let empty = Label.create(card.body, appStrings().ui_NoDriveMounted, {}, null, .SecondaryText)
        empty.dockStyle = .Center
        empty.setTextAlignment(.Center, .Center)

        var result: retval
        result.card          = card
        result.list          = list
        result.empty         = empty
        result.unmountButton = unmount
        result.refresh()
        return result
    }

    // Says the table again from `drives`.
    mtd refresh()
    {
        .list.clear()
        for &one in .drives
        {
            let line = .list.createLine("")
            line.canCheck = true

            // The padlock is the whole of what says the drive is read only, so it stands on the
            // letter itself: a mark in the vault column would read as a property of the file,
            // and the file is exactly as writable as it ever was.
            var driveIcon: Icon
            if one.readOnly do
                driveIcon = .list.theme().icon(ThemeIcons.Lock, LockIconSize)
            line.setItem(cast(u32) MountedColumn.Drive, one.drive.toString(), driveIcon)
            line.setItem(cast(u32) MountedColumn.Vault, Path.fileName(one.path.toString()) orelse one.path.toString())
        }

        for &one, index in .drives where one.atStartup do
            .list.setLineChecked(cast(u32) index, true, notify: false)

        let filled = !.drives.isEmpty()
        .list.show(filled)
        .empty.show(!filled)
        .card.body.applyLayout()

        if filled
        {
            if !.list.selectedLine() do
                .list.selectLine(0)
            .layoutColumns()
        }

        .sigDrivesChanged.call(me)
    }

    // Gives the vault column whatever the two fixed ones leave.
    //
    // Measured against what the header actually occupies rather than against the sum of the
    // column widths: the separators and the leading padding are part of that width, and a
    // table one separator too wide answers with a horizontal scroll bar.
    mtd layoutColumns()
    {
        let vault     = cast(u32) MountedColumn.Vault
        let available = .list.listView.paddedClientRect().width
        let others    = .list.header.contentWidth() - .list.header.itemWidthForColumn(vault)
        .list.setColumnWidth(vault, Math.max(MinimumVaultWidth, available - others))
        .list.computeLayout()
    }

    // Returns the drive the list is on, or `Swag.U64.Max` when it is on none.
    mtd selectedIndex()->u64
    {
        let line = .list.selectedLine()
        if !line do
            return Swag.U64.Max
        for &one, index in .drives
        {
            discard one
            if .list.lineAt(cast(u32) index) == line do
                return index
        }

        return Swag.U64.Max
    }

    // Hands over the mount at `index` and drops its row.
    //
    // The caller becomes responsible for closing and releasing what it gets back: this card
    // holds a mount only while it shows it.
    mtd detach(index: u64)->#null *WinFsp.MountedVolume
    {
        Debug.assert(index < .drives.count)
        let result = .drives[index].volume
        .drives.removeAtOrdered(index)
        .refresh()
        return result
    }

    // Says the heading, the explanation, the column names and the action again in the language
    // now active.
    mtd retranslate()
    {
        .card.setTexts(appStrings().ui_MountedCardTitle, appStrings().ui_MountedCardHelp)
        .list.header.itemAt(cast(u32) MountedColumn.Startup).name = appStrings().ui_ColStartup
        .list.header.itemAt(cast(u32) MountedColumn.Drive).name   = appStrings().ui_ColDrive
        .list.header.itemAt(cast(u32) MountedColumn.Vault).name   = appStrings().ui_ColVault
        .list.header.invalidate()

        .empty.setText(appStrings().ui_NoDriveMounted)
        .unmountButton.setText(appStrings().ui_Unmount)
        .card.actions.computeLayout()
        .card.endForm()
    }
}
