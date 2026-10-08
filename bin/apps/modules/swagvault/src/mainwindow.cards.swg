impl MainWindow
{
    // Creates the product name and the sentence under it.
    mtd createHeader()
    {
        // The header is as tall as the two rows it holds, so a wrapped explanation is not
        // cut off by a height calibrated on the shortest of the shipped languages.
        with let header = StackLayoutCtrl.create(me, .Top)
        {
            .dockStyle = .Top
            .margin    = {32, 20, 32, 0}
            .spacing   = 4
        }

        with let titleRow = Wnd.create'Wnd(header, {0, 0, 0, 44})
        {
            .dockStyle = .Top
        }

        let titleFont = .theme().createDefaultFont(34, .Bold)

        with let title = Label.create(titleRow, ProductName)
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
            .style.setFont(titleFont, .Regular)
        }

        // The row is as tall as the line box of the name. A hand-tuned height clips it, and by a
        // fraction of a pixel: enough to cut a descender, not enough to be noticed until the name
        // is set in another face.
        titleRow.resize(titleRow.position.width, Math.max(titleRow.position.height, titleFont.height))

        with .subtitle = Label.create(header, appStrings().ui_Subtitle, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        {
            .dockStyle = .Top
            .setTextAlignment(.Left, .Top)
        }

        titleRow.applyLayout()
        header.computeLayout()
    }

    // Creates the attribution row and, above it, the status line.
    mtd createFooter()
    {
        with let footerRow = Wnd.create'Wnd(&.wnd, {0, 0, 0, 24})
        {
            .dockStyle = .Bottom
            .margin    = {32, 0, 32, 12}
        }

        // The attribution keeps what it owes: the product, the holder, and where it comes from.
        // Expanding the acronym as well made the line the widest thing on the surface, and the
        // window is now one card wide.
        with let credit = Label.create(footerRow, "WinFsp — Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp", {}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
        }

        footerRow.applyLayout()

        // The status line is raised off the ground by the same slight panel shape as the card. A
        // border around it would draw a third box on a surface that already reads without one.
        with .statusView = Wnd.create'Wnd(&.wnd, {0, 0, 0, 52})
        {
            .dockStyle       = .Bottom
            .margin          = {32, 0, 32, 12}
            .backgroundStyle = .Panel
            .padding         = {20, 8, 20, 8}
        }

        with .statusIcon = Label.create(.statusView, "", {0, 0, 24})
        {
            .dockStyle = .Left
            .margin.z  = 12
        }

        // The spinner takes the glyph's place rather than a slot of its own: it is the same
        // 24-pixel square, and a docked window that is hidden takes no room, so the status text
        // starts at the same column whether work is running or not.
        with .statusBusy = Spinner.create(.statusView, {0, 0, 24, 24})
        {
            .dockStyle = .Left
            .margin.z  = 12
            .hide()
        }

        with .status = Label.create(.statusView, "")
        {
            .dockStyle = .Center
            .setTextAlignment(.Left, .Center)
        }

        .statusView.applyLayout()
    }

    // Creates the page listing the drives this window exposes.
    mtd createMountedDrivesCard(parent: *Wnd)->*Wnd
    {
        with .mountedDrives = MountedDrives.create(parent)
        {
            .unmountButton.sigPressed += func|window = me|(?) { window.unmountSelectedDrive() }
            .list.sigSelectionChanged += func|window = me|(?) { window.refreshActions() }
            .sigDrivesChanged         += func|window = me|(?) { window.refreshActions() }
            .list.sigCheckedChanged   += func|window = me|(?) { window.applyStartupMarks() }
        }

        // The semantic column shares are resolved again every time the table receives a new
        // width, so the header covers the complete logical client area at every surface size.
        .mountedDrives.list.listView.hookOnEvent = func|window = me|(?, evt)
        {
            if evt is ResizeEvent do
                window.mountedDrives.layoutColumns()
            return false
        }

        return .mountedDrives.card.panel
    }

    // Creates the privacy and automatic-unmount page.
    mtd createOptionsCard(parent: *Wnd)->*Wnd
    {
        .optionsCard = VaultCard.create(parent, appStrings().ui_OptionsCardTitle, appStrings().ui_OptionsCardHelp)
        .optionsCard.actions.hide()

        let form = .optionsCard.form
        .privacyModeControl = form.addOptionField(appStrings().ui_PrivacyMode, help: appStrings().ui_PrivacyModeHelp)
        .unmountOnLock      = form.addOptionField(appStrings().ui_UnmountOnLock, help: appStrings().ui_UnmountOnLockHelp)
        .unmountOnSuspend   = form.addOptionField(appStrings().ui_UnmountOnSuspend, help: appStrings().ui_UnmountOnSuspendHelp)
        .unmountOnIdle      = form.addOptionField(appStrings().ui_UnmountOnIdle, help: appStrings().ui_UnmountOnIdleHelp)
        .idleTimeout        = form.addChoiceField(appStrings().ui_IdleTimeout)

        for minutes in IdleChoices do
            .idleTimeout.addItem(Format.toString(appStrings().ui_Minutes, minutes))

        .privacyModeControl.sigChanged += func|window = me|(?) { window.readPrivacyControl() }
        for check in [.unmountOnLock, .unmountOnSuspend, .unmountOnIdle] do
            check.sigChanged += func|window = me|(?) { window.readAutoUnmountControls() }
        .idleTimeout.sigChanged += func|window = me|(?, ?) { window.readAutoUnmountControls() }
        .applyPrivacyControl()
        .applyAutoUnmountControls()
        .optionsCard.endForm()
        return .optionsCard.panel
    }

    // Creates the page that makes a new container.
    mtd createNewVaultCard(parent: *Wnd)->*Wnd
    {
        .createCard = VaultCard.create(parent, appStrings().ui_CreateCardTitle, appStrings().ui_CreateCardHelp)
        let card     = &.createCard
        let form     = card.form
        let fileIcon = .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics()))

        with .createPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: "C:\\path\\private", icon: fileIcon)
        {
            .updateFlags(.AcceptFileDrop)
            setMachineFont(me.createPath)
        }

        with .browseCreate = form.addRowAction(appStrings().ui_Browse, fileIcon)
        {
            .sigPressed += func|window = me|(?) { window.chooseContainer(window.createPath, true) }
        }

        with .createSize = form.addTextField(appStrings().ui_FixedCapacity, "256")
        {
            .setUnsignedIntegerRange(1, 1024 * 1024)
            setMachineFont(me.createSize)
        }

        .createUnit = VaultForm.addCapacityUnit(form)

        // The password is optional, and the card explains that above rather than under the
        // field: it is a fact about what this card produces, not a note about one control.
        .createPassword  = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_OptionalPassword)
        .confirmPassword = form.addPasswordField(appStrings().ui_ConfirmPassword, placeholder: appStrings().ui_EnterAgain)
        .createKeyFiles  = KeyFileField.create(form)
        discard form.addField(appStrings().ui_KeyFiles, .createKeyFiles, help: appStrings().ui_KeyFilesHelp)

        // Creation is long enough to be worth stopping, so its own button becomes the way out
        // of it. A second control would sit dead on the card the rest of the time, and the card
        // already has one dominant action.
        //
        // It carries no width for that very reason: the caption changes with the state and
        // with the language, so the layout pass reads it from the button rather than from a
        // number tuned on one wording.
        with .createButton = PushButton.create(card.actions, appStrings().ui_CreateVault, form: .Strong)
        {
            .setIcon(me.theme().icon(.SaveAs, themeActionIconSize(me.themeMetrics())))
            .sigPressed += func|window = me|(?)
            {
                if window.operation.kind == .Create do
                    window.stopLongOperation()
                else do
                    window.createContainer()
            }
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    // Creates the page that mounts, resizes, and re-keys an existing container.
    mtd createOpenVaultCard(parent: *Wnd)->*Wnd
    {
        .mountCard = VaultCard.create(parent, appStrings().ui_MountCardTitle, appStrings().ui_MountCardHelp)
        let card     = &.mountCard
        let form     = card.form
        let fileIcon = .theme().icon(.OpenFile, themeRowIconSize(.themeMetrics()))

        with .mountPath = form.addTextField(appStrings().ui_ContainerFile, placeholder: appStrings().ui_ExistingContainer, icon: fileIcon)
        {
            .updateFlags(.AcceptFileDrop)
            setMachineFont(me.mountPath)
        }

        with .browseMount = form.addRowAction(appStrings().ui_Browse, fileIcon)
        {
            .sigPressed += func|window = me|(?) { window.chooseContainer(window.mountPath, false) }
        }

        .mountPassword = form.addPasswordField(appStrings().ui_Password, placeholder: appStrings().ui_ContainerPassword)
        with .hiddenButton = form.addRowAction(appStrings().ui_CreateHidden)
        {
            .sigPressed += func|window = me|(?) { window.createHiddenContainer() }
        }

        .mountKeyFiles = KeyFileField.create(form, canGenerate: false)
        discard form.addField(appStrings().ui_KeyFiles, .mountKeyFiles, help: appStrings().ui_KeyFilesHelp)

        // The lifetime of the drive belongs to the letter that carries it, so it is said under
        // that field rather than as a loose paragraph at the bottom of the card.
        .drive = form.addChoiceField(appStrings().ui_DriveLetter, help: appStrings().ui_DriveHelp)
        setMachineFont(.drive)
        .fillDriveChoice()

        // Under the letter rather than beside the password: it says what the drive will be, not
        // how the container is opened, and a reader deciding on a letter is already there.
        with .mountOptions = StackLayoutCtrl.create(form, .Left)
        {
            .spacing = form.themeMetrics().dialog_BtnPadding * 3
        }

        discard form.addField("", .mountOptions)
        .readOnly            = CheckButton.create(.mountOptions, appStrings().ui_ReadOnly)
        .protectHidden       = CheckButton.create(.mountOptions, appStrings().ui_ProtectHidden)
        .readOnly.sigChanged += func|window = me|(button) { window.protectHidden.enable(not button.isChecked()) }

        // The action bar stacks from its right edge, so the dominant action is created first and
        // ends up under the reader's thumb, with the two secondary ones to its left.
        //
        // The remaining actions are secondary on purpose: mounting is what a reader comes to this
        // card for. Each box asks only for the value it changes; the current password and key files
        // are stated once in this form and consumed from here.
        with .mountButton = PushButton.create(card.actions, appStrings().ui_MountDrive, form: .Strong)
        {
            .setIcon(me.theme().icon(.Play, themeActionIconSize(me.themeMetrics())))
            .sigPressed += func|window = me|(?) { window.mountContainer() }
        }

        with .resizeButton = PushButton.create(card.actions, appStrings().ui_Resize)
        {
            .sigPressed += func|window = me|(?)
            {
                if window.operation.kind == .Resize do
                    window.stopLongOperation()
                else do
                    window.resizeVault()
            }
        }

        with .passwordButton = PushButton.create(card.actions, appStrings().ui_ChangePassword)
        {
            .sigPressed += func|window = me|(?) { window.changeVaultPassword() }
        }

        with .keyFilesButton = PushButton.create(card.actions, appStrings().ui_ChangeKeyFiles)
        {
            .sigPressed += func|window = me|(?) { window.changeVaultKeyFiles() }
        }

        card.actions.computeLayout()
        card.endForm()
        return card.panel
    }

    // Fills the picker with the destinations the active filesystem backend still has free.
    //
    // Mounting takes one and unmounting gives it back, so the list is said again after both:
    // a letter that is no longer free must not stay on offer.
    mtd fillDriveChoice()
    {
        let previous = .selectedMountPoint()
        .drive.clear()

        .mountDestinations = availableMountDestinations()
        for &destination in .mountDestinations do
            .drive.addItem(destination.label)

        if .drive.items.count and not .selectMountPoint(previous) do
            .drive.setSelectedIndex(0, notify: false)
    }

    // Selects `mountPoint` when that backend destination is still available.
    mtd selectMountPoint(mountPoint: string)->bool
    {
        for &destination, index in .mountDestinations where destination.id == mountPoint
        {
            .drive.setSelectedIndex(cast(u32, index), notify: false)
            return true
        }

        return false
    }

    // Restores the non-secret choices of the last successful mount into the form.
    mtd restoreMountSettings()
    {
        if not .mountSettings.path.isEmpty() do
            .mountPath.setText(.mountSettings.path)
        if not .mountSettings.drive.isEmpty() do
            discard .selectMountPoint(.mountSettings.drive)
        .readOnly.setState(.mountSettings.readOnly ? .Checked : .Unchecked)
    }

    // Lets the reader pick the container file `target` names, for creating it or for opening it.
    mtd chooseContainer(target: *EditBox, create: bool)
    {
        // Privacy controls persistence, not the convenience of returning to the last folder
        // during this run. Serialization below remains the only path from this state to disk.
        with var options: FileDlgOptions
        {
            .state             = &me.fileDlgState
            .mode              = create ? .CreateFile : .SelectFile
            .title             = create ? appStrings().dlg_TitleCreate : appStrings().dlg_TitleOpen
            .confirmButtonText = create ? appStrings().dlg_BtnCreate : appStrings().dlg_BtnOpen
            .initialName       = create ? "volume" : ""
            .shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
            .shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})
        }

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            target.setText(dialog.selectedPath())
    }

    // Returns the backend identifier of the destination the picker selects, or an empty string.
    mtd selectedMountPoint()->String
    {
        let index = .drive.selectedIndex
        return index < .mountDestinations.count ? .mountDestinations[index].id : ""
    }

    // Returns the host-facing name for a backend destination identifier.
    mtd mountPointLabel(mountPoint: string)->String
    {
        for &destination in .mountDestinations where destination.id == mountPoint do
            return destination.label
        return mountPoint
    }
}
