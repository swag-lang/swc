#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func releaseAfterNativeClose(thread: const *Threading.Thread)
{
    let activity = cast(*MountActivity, unwrap thread.userParam)
    Threading.Thread.sleep(1'ms)
    activity.release()
}

// A posted native close wakes the bounded drain without an arbitrary polling delay.
#test
{
    var activity: MountActivity
    activity.handles = 1
    var worker: Threading.Thread
    expect worker.init(&releaseAfterNativeClose, &activity)
    expect worker.start()
    defer worker.wait()
    expect activity.beginStop(false, 500)
    Swag.require(activity.stopping and activity.handles == 0)
}

// A refused stop leaves admission open, while force closes admission despite live handles.
#test
{
    var activity: MountActivity
    activity.handles = 2
    var error: Swag.Error
    catch activity.beginStop(false) as error
    Swag.require(isBusyError(error.value()))
    Swag.require(not activity.stopping and activity.handles == 2)
    activity.release()
    activity.release()
    expect activity.beginStop(false)
    Swag.require(activity.stopping)
    activity.cancelStop()
    activity.handles = 1
    expect activity.beginStop(true)
    Swag.require(activity.stopping and activity.handles == 1)
}

#static if WINDOWS
{
    func addUnmountFixture(window: *MainWindow, path: string, busy: bool)->*WinFsp.MountedVolume
    {
        let native = Memory.new'WinFsp.MountedVolume()
        native.volume               = expect Volume.create(path, "", MinimumSize)
        native.volumeOpen           = true
        native.mount.context        = Memory.new'WinFsp.NativeMountContext()
        native.mount.context.volume = &native.volume
        native.mount.context.activity.handles = busy ? 1 : 0
        let mount = Memory.new'MountedVault()
        mount.handle = native
        var entry: MountedDrive
        entry.volume        = mount
        entry.path          = path
        entry.needsPassword = true
        window.mountedDrives.drives.add(entry)
        window.addVault(path)
        return native
    }

    // Exercise actual native create/open/close admission without loading the driver.
    #test
    {
        let path = Testing.tempFilePath("vault-busy-", ".bin")
        defer discard catch File.delete(path)
        var mounted: WinFsp.MountedVolume
        mounted.volume               = expect Volume.create(path, "", MinimumSize)
        mounted.volumeOpen           = true
        mounted.mount.context        = Memory.new'WinFsp.NativeMountContext()
        mounted.mount.context.volume = &mounted.volume
        var fileSystem: WinFsp.FspFileSystem
        fileSystem.userContext = mounted.mount.context
        var context: *void?
        var info:    WinFsp.FileInfo
        let root = Utf16.toZeroTerminated("\\")
        Swag.require(WinFsp.fspOpen(&fileSystem, root.buffer, 0, 0, &context, &info) == WinFsp.StatusSuccess)
        var error: Swag.Error
        catch mounted.close() as error
        Swag.require(isBusyError(error.value()))
        Swag.require(mounted.volumeOpen and mounted.mount.context != null)
        Swag.require(not mounted.mount.context.activity.stopping)
        WinFsp.fspClose(&fileSystem, context)
        expect mounted.close()
        Swag.require(not mounted.volumeOpen and mounted.mount.context == null)
        expect mounted.close()
    }

    // Force closes admission atomically; no later native open or create can sneak in.
    #test
    {
        let path = Testing.tempFilePath("vault-force-", ".bin")
        defer discard catch File.delete(path)
        var mounted: WinFsp.MountedVolume
        mounted.volume               = expect Volume.create(path, "", MinimumSize)
        mounted.volumeOpen           = true
        mounted.mount.context        = Memory.new'WinFsp.NativeMountContext()
        mounted.mount.context.volume = &mounted.volume
        var fileSystem: WinFsp.FspFileSystem
        fileSystem.userContext = mounted.mount.context
        var context: *void?
        var info:    WinFsp.FileInfo
        let root = Utf16.toZeroTerminated("\\")
        let file = Utf16.toZeroTerminated("\\refused")
        Swag.require(WinFsp.fspOpen(&fileSystem, root.buffer, 0, 0, &context, &info) == WinFsp.StatusSuccess)
        expect mounted.mount.context.activity.beginStop(true)
        Swag.require(WinFsp.fspOpen(&fileSystem, root.buffer, 0, 0, &context, &info) == WinFsp.StatusAccessDenied)
        Swag.require(WinFsp.fspCreate(&fileSystem, file.buffer, 0, 0, 0, null, 0, &context, &info) == WinFsp.StatusAccessDenied)
        expect mounted.close(force: true)
        Swag.require(not mounted.volumeOpen and mounted.mount.context == null)
        var reopened = expect Volume.open(path, "")
        Swag.require(reopened.resolve("/refused") == null)
    }

    // WinFsp can stop without posting Close for every handle. An ordinary unmount still
    // releases the container and commits accepted writes after its final callback.
    #test
    {
        let path = Testing.tempFilePath("vault-dispatch-stopped-", ".bin")
        defer discard catch File.delete(path)
        var mounted: WinFsp.MountedVolume
        mounted.volume               = expect Volume.create(path, "", MinimumSize)
        mounted.volumeOpen           = true
        mounted.mount.context        = Memory.new'WinFsp.NativeMountContext()
        mounted.mount.context.volume = &mounted.volume
        var fileSystem: WinFsp.FspFileSystem
        fileSystem.userContext = mounted.mount.context
        var context: *void?
        var info:    WinFsp.FileInfo
        let file    = Utf16.toZeroTerminated("\\accepted")
        let created = WinFsp.fspCreate(&fileSystem, file.buffer, 0, 0, 0, null, 0, &context, &info)
        Swag.require(created == WinFsp.StatusSuccess)
        Swag.require(mounted.mount.context.activity.handles == 1)

        let dispatch = WinFsp.makeInterface()
        (dispatch.dispatcherStopped)(&fileSystem, 0)
        expect mounted.close()
        Swag.require(not mounted.volumeOpen and mounted.mount.context == null)
        var reopened = expect Volume.open(path, "")
        Swag.require(reopened.resolve("/accepted") != null)
    }

    // Canceling a quit leaves a genuinely busy drive available for an ordinary retry.
    #test
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        let path   = Testing.tempFilePath("vault-resident-busy-", ".bin")
        defer discard catch File.delete(path)
        let native = Memory.new'WinFsp.MountedVolume()
        native.volume               = expect Volume.create(path, "", MinimumSize)
        native.volumeOpen           = true
        native.mount.context        = Memory.new'WinFsp.NativeMountContext()
        native.mount.context.volume = &native.volume
        native.mount.context.activity.handles = 1
        let mount = Memory.new'MountedVault()
        mount.handle = native
        var entry: MountedDrive
        entry.volume        = mount
        entry.path          = path
        entry.needsPassword = true
        window.mountedDrives.drives.add(entry)
        window.addVault(path)

        window.handleAutoUnmount(.SessionLock)
        Swag.require(window.mountedDrives.drives.count == 1 and mount.handle != null)
        Swag.require(window.statusMessage == .AutoUnmountBusy)
        host.clickModalButtonWhenShown(Dialog.BtnCancel)
        var close = SysCommandEvent{kind: .Close}
        window.sendEvent(&close)
        Swag.require(close.accepted)
        window.operation.task.wait()
        window.finishOperation()
        Swag.require(window.mountedDrives.drives.count == 1 and mount.handle != null)
        Swag.require(host.autoHandled and window.statusDetail.isEmpty())
        Swag.require(not window.resident.quitting and not window.resident.batch)
        Swag.require(window.statusMessage == .UnmountStopped)
        Swag.require(not window.isPendingDestroy)
        native.mount.context.activity.release()
        window.resident.unmountAll(quit: false)
        window.operation.task.wait()
        window.finishOperation()
        Swag.require(window.mountedDrives.drives.count == 0)
        Swag.require(window.statusMessage == .Unmounted)
    }

    // The confirmed force retry acts only on the drive that survived the ordinary batch.
    #test
    {
        var host: Testing.HeadlessHost
        host.setup(640, 480)
        host.bindApplication(&g_App)
        registerAppStrings(&g_App.resources)
        registerAppStrings(&host.app.resources)
        Gui.registerLanguage("fr", "Français")
        expect host.app.setLanguage("fr")
        defer expect host.app.setLanguage(ReferenceLanguage)
        let surface  = expect host.app.createSurface(0, 0, MainWindow.MinWidth, MainWindow.MinHeight)
        let window   = MainWindow.create(surface.wnd)
        let busyPath = Testing.tempFilePath("vault-partial-busy-", ".bin")
        let idlePath = Testing.tempFilePath("vault-partial-idle-", ".bin")
        defer discard catch File.delete(busyPath)
        defer discard catch File.delete(idlePath)
        let busy = addUnmountFixture(window, busyPath, true)
        discard addUnmountFixture(window, idlePath, false)
        window.resident.settings.enabled = true
        window.resident.showWindow()
        window.resident.setEnabled(false)
        host.clickModalButtonWhenShown(Dialog.BtnOk)
        var close = SysCommandEvent{kind: .Close}
        window.sendEvent(&close)
        window.sendEvent(&close)
        for 2
        {
            window.operation.task.wait()
            window.finishOperation()
        }

        Swag.require(window.mountedDrives.drives.count == 1)
        Swag.require(window.mountedDrives.drives[0].path == busyPath)
        Swag.require(busy.volumeOpen and window.resident.quitting)
        Swag.require(host.autoHandled and window.operation.forceUnmount)
        Swag.require(window.statusDrive == "1" and window.statusDetail.isEmpty())
        window.operation.task.wait()
        window.finishOperation()
        Swag.require(window.mountedDrives.drives.count == 0 and not window.resident.batch)
        Swag.require(surface.wnd.isPendingDestroy)
        host.pump()
        Swag.require(host.app.surfaces.count == 1)
    }

    // A detached drive's synchronization failure keeps the window open.
    #test
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        let path   = Testing.tempFilePath("vault-unmount-sync-", ".bin")
        defer discard catch File.delete(path)
        let native = addUnmountFixture(window, path, false)
        native.volume.touchScalars()
        native.volume.file.protectionTriggered = true

        host.clickModalButtonWhenShown(Dialog.BtnOk)
        var close = SysCommandEvent{kind: .Close}
        window.sendEvent(&close)
        window.operation.task.wait()
        window.finishOperation()
        Swag.require(host.autoHandled and not window.isPendingDestroy)
        Swag.require(window.mountedDrives.drives.isEmpty())
        Swag.require(window.operation.kind == .None and
                     not window.resident.quitting and
                     not window.resident.batch)
        Swag.require(window.statusMessage == .UnmountSyncStopped and window.statusDetail.isEmpty())
    }
}

#static if #os == Swag.TargetOs.Linux
{
    // FUSE files and directory descriptors participate in the same admission contract.
    #test
    {
        let path = Testing.tempFilePath("vault-fuse-handles-", ".bin")
        defer discard catch File.delete(path)
        var owner: Fuse.MountedVolume
        owner.volume     = expect Volume.create(path, "", MinimumSize)
        owner.volumeOpen = true
        var file: Linux.fuse_file_info
        file.flags = Linux.O_RDWR
        Swag.require(Fuse.callbackCreate(&owner, "/file".buffer, 0x180, &file) == 0)
        Swag.require(owner.activity.handles == 1)
        var error: Swag.Error
        catch owner.activity.beginStop(false) as error
        Swag.require(isBusyError(error.value()))
        Swag.require(Fuse.callbackRelease(&owner, &file) == 0 and file.fh == 0)
        var directory: Linux.fuse_file_info
        Swag.require(Fuse.callbackOpendir(&owner, "/".buffer, &directory) == 0)
        Swag.require(owner.activity.handles == 1)
        Swag.require(Fuse.callbackRelease(&owner, &directory) == 0)
        expect owner.activity.beginStop(false)
        Swag.require(Fuse.callbackOpen(&owner, "/file".buffer, &file) == -Linux.EBUSY)
        Swag.require(Fuse.callbackCreate(&owner, "/refused".buffer, 0x180, &file) == -Linux.EBUSY)
        Swag.require(owner.volume.resolve("/refused") == null)
    }
}
