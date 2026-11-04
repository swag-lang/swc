#global if #os == Swag.TargetOs.Linux

using Core

namespace Fuse
{
    struct Runtime
    {
        library:       *void?
        references:    u64
        late create:   Linux.fuse_new_fn
        late mount:    Linux.fuse_mount_fn
        late exit:     Linux.fuse_void_fn
        late unmount:  Linux.fuse_void_fn
        late destroy:  Linux.fuse_void_fn
        late loop:     Linux.fuse_loop_fn
        late context:  Linux.fuse_get_context_fn
        late freeArgs: Linux.fuse_opt_free_args_fn
    }

    private var g_Runtime:      *Runtime?
    private var g_RuntimeMutex: Swag.Mutex

    func acquireRuntime()->*Runtime fail
    {
        g_RuntimeMutex.lock()
        defer g_RuntimeMutex.unlock()
        if g_Runtime
        {
            g_Runtime!.references += 1
            return unwrap g_Runtime
        }

        func(T) symbol(library: *void, name: string)->T fail
        {
            let address = Linux.dlsym(library, name.buffer)
            if not address do
                fail volumeError(.DriverUnavailable)
            return cast(T, address)
        }

        var library = Linux.dlopen("libfuse3.so.4".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        if not library do
            library = Linux.dlopen("libfuse3.so.3".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        if not library do
            fail volumeError(.DriverUnavailable)
        defer #fail discard Linux.dlclose(unwrap library)
        let result = Memory.new'Runtime()
        defer #fail Memory.delete(result)
        result.library    = library
        result.create     = try symbol'Linux.fuse_new_fn(library, "fuse_new_31")
        result.mount      = try symbol'Linux.fuse_mount_fn(library, "fuse_mount")
        result.exit       = try symbol'Linux.fuse_void_fn(library, "fuse_exit")
        result.unmount    = try symbol'Linux.fuse_void_fn(library, "fuse_unmount")
        result.destroy    = try symbol'Linux.fuse_void_fn(library, "fuse_destroy")
        result.loop       = try symbol'Linux.fuse_loop_fn(library, "fuse_loop")
        result.context    = try symbol'Linux.fuse_get_context_fn(library, "fuse_get_context")
        result.freeArgs   = try symbol'Linux.fuse_opt_free_args_fn(library, "fuse_opt_free_args")
        result.references = 1
        g_Runtime         = result
        return result
    }

    func releaseRuntime(runtime: *Runtime)
    {
        g_RuntimeMutex.lock()
        defer g_RuntimeMutex.unlock()
        runtime.references -= 1
        if runtime.references do
            return
        discard Linux.dlclose(unwrap runtime.library)
        g_Runtime = null
        Memory.delete(runtime)
    }

    func current()->*MountedVolume
    {
        let context = (g_Runtime!.context)()
        return cast(*MountedVolume, unwrap context.private_data)
    }

    #[Swag.NoCopy]
    struct MountedVolume
    {
        volume:             Volume
        volumeOpen:         bool
        runtime:            *Runtime?
        native:             *void?
        mounted:            bool
        createdDestination: bool
        destination:        String
        worker:             Threading.Thread
        workerStarted:      bool
        ready:              u32
        uid:                u32
        gid:                u32
    }

    impl MountedVolume
    {
        mtd start(path: string, password: const [..]u8, target: string, readOnly: bool, protectionPassword: const [..]u8) fail
        {
            if target.count == 0 or target[0] != '/' or not Utf8.isValid(target) do
                fail volumeError(.InvalidInput)
            for byte in target where byte == 0 do
                fail volumeError(.InvalidInput)
            .destination = target
            .uid         = Linux.geteuid()
            .gid         = Linux.getegid()
            if not Directory.exists(target)
            {
                let made = Linux.mkdirat(Linux.AT_FDCWD, unwrap .destination.buffer, 0x1C0)
                if made != 0 do
                    fail volumeError(.AccessDenied, cast(u64, Linux.errno()))
                .createdDestination = true
            }

            var info: Linux.stat
            if Linux.fstatat(Linux.AT_FDCWD, unwrap .destination.buffer, &info, Linux.AT_SYMLINK_NOFOLLOW) != 0 or
               (info.st_mode & Linux.S_IFMT) != Linux.S_IFDIR or
               info.st_uid != .uid or
               (info.st_mode & (Linux.S_IWGRP | Linux.S_IWOTH)) != 0 do
                fail volumeError(.AccessDenied)
            let entries = try Directory.enumerate(target, {})
            if not entries.isEmpty() do
                fail volumeError(.DirectoryNotEmpty)

            .volume     = try Volume.open(path, password, readOnly, protectionPassword)
            .volumeOpen = true
            .runtime    = try acquireRuntime()
            var program = String.from("swagvault")
            var flag    = String.from("-o")
            var options = String.from("fsname=SwagVault,subtype=swagvault,default_permissions,attr_timeout=0,entry_timeout=0,negative_timeout=0")
            if readOnly do
                options += ",ro"
            var arguments: [3](*u8?) = [cast(*u8?, program.buffer), cast(*u8?, flag.buffer), cast(*u8?, options.buffer)]
            var args = Linux.fuse_args{argc: 3, argv: &arguments[0]}
            defer (.runtime!.freeArgs)(&args)
            let operations = makeOperations()
            .native = (.runtime.create)(&args, &operations, #sizeof(Linux.fuse_operations), me)
            if not .native do
                fail volumeError(.DriverUnavailable)
            if (.runtime.mount)(.native, .destination.buffer) != 0 do
                fail volumeError(.DriverUnavailable, cast(u64, Linux.errno()))
            .mounted = true
            Atomic.exchange(&.ready, 0)
            try .worker.init(&serve, me)
            try .worker.start()
            .workerStarted = true
            let deadline = Time.monotonicMilliseconds() + 5000
            while Atomic.get(&.ready) == 0 and Time.monotonicMilliseconds() < deadline do
                Threading.Thread.sleep(Time.Duration.fromMilliseconds(1))
            if Atomic.get(&.ready) != 1 do
                fail volumeError(.DriverUnavailable)
        }

        mtd stop()
        {
            // Detaching wakes fuse_loop and prevents new kernel requests. Join before any
            // callback-visible memory, crypto keys or the dynamic library can disappear.
            if .mounted
            {
                (.runtime!.exit)(unwrap .native)
                (.runtime.unmount)(.native)
                .mounted = false
            }

            if .worker.isValid()
            {
                if not .workerStarted
                {
                    .worker.userLambda = null
                    expect .worker.start()
                }

                .worker.wait()
                .workerStarted = false
            }

            if .native
            {
                (.runtime!.destroy)(.native)
                .native = null
            }

            if .runtime
            {
                releaseRuntime(.runtime)
                .runtime = null
            }

            if .createdDestination
            {
                discard catch Directory.delete(.destination)
                .createdDestination = false
            }
        }

        mtd close() fail
        {
            .stop()
            if not .volumeOpen do
                return
            defer
            {
                .volume.close()
                .volumeOpen = false
            }

            if .volume.dirty and not .volume.readOnly do
                try .volume.commit()
        }

        mtd opDrop() { discard catch .close() }
    }

    private func serve(thread: const *Threading.Thread)
    {
        let owner = cast(*MountedVolume, unwrap thread.userParam)
        discard (owner.runtime!.loop)(unwrap owner.native)
        Atomic.exchange(&owner.ready, 2)
    }
}

func mountVaultNative(path: string, password: const [..]u8, destination: string, readOnly: bool, protectionPassword: const [..]u8)->*void fail
{
    let owner = Memory.new'Fuse.MountedVolume()
    defer #fail Memory.delete(owner)
    try owner.start(path, password, destination, readOnly, protectionPassword)
    return owner
}

func unmountVaultNative(handle: *void) fail
{
    let owner = cast(*Fuse.MountedVolume, handle)
    defer Memory.delete(owner)
    try owner.close()
}

func mountedVaultSpaceNative(handle: *void)->MountedVaultSpace
{
    let owner = cast(*Fuse.MountedVolume, handle)
    owner.volume.accessLock.lockShared()
    defer owner.volume.accessLock.unlockShared()
    return {total: owner.volume.totalBytes(), available: owner.volume.freeBytes()}
}

func availableMountDestinationsNative()->Array'MountDestination
{
    var result: #returntype
    let base = Path.combine(Env.getSpecialDirectory(.UserAppData), "swag", "vault", "mounts")
    catch Directory.create(base, true) do return result
    for index in 1 until 17
    {
        let path = Path.combine(base, Format.toString("volume%", index))
        if not Directory.exists(path) do
            result.add({id: path, label: path})
    }

    return result
}

func isMountHostInvocationNative()->bool => false

// Linux serves mounts in this process; there is no helper command to execute.
func runMountHostNative()->s32 => 1
