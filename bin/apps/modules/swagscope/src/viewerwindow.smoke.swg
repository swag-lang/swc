impl ViewerWindow
{
    // Starts the application smoke review. Each registered viewer owns one immutable fixture;
    // the real window opens them in registry order and explicitly selects the owner, including
    // the Binary and Hexadecimal viewers that normally appear as alternatives.
    mtd reviewSmokeFixtures(directory: string)
    {
        var absolute = catch Path.absolute(directory) as pathError
        if pathError != null or not Directory.exists(absolute)
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture directory is missing: %", directory))
            return
        }

        .smokeDirectory = #move absolute
        .smokeSpecIndex = 0
        .smokeWaitSteps = 0
        .smokeOpened    = false
        .smokeSelected  = false
        .smokeRunning   = true

        // A 10 ms cadence leaves the viewers' own 4-8 ms progressive timers a dispatch turn
        // between readiness checks instead of letting the review timer dominate a smoke loop.
        .smokeTimer = .addTimer(10'ms)
    }

    private mtd finishSmokeReview(exitCode: s32, message: string)
    {
        if message.count do
            Console.println(message)
        .stopTimer(&.smokeTimer)

        .smokeRunning = false
        .app().postQuitEvent(exitCode)
    }

    private mtd waitForSmokeViewer(key, fileName: string)
    {
        .smokeWaitSteps += 1
        if .smokeWaitSteps <= SmokeStepLimit do
            return

        .finishSmokeReview(1, Format.toString("Swag Scope smoke viewer '%' did not finish '%' after % readiness checks", key, fileName, SmokeStepLimit))
    }

    // Advances the smoke review by one timer step: opens each plugin's fixture, selects that
    // plugin's viewer, and keeps it exposed long enough for late failures to surface. Quits with
    // exit code 1 on the first failure.
    private mtd reviewSmokeStep()
    {
        if .smokeSpecIndex >= .index.plugins.count
        {
            .finishSmokeReview(0, Format.toString("Swag Scope smoke reviewed % viewer plugins", .index.plugins.count))
            return
        }

        let plugin  = &.index.plugins[.smokeSpecIndex]
        let key     = plugin.key
        let fixture = plugin.smokeFixture

        let fileName = Path.combine(.smokeDirectory, fixture)
        if not File.exists(fileName)
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture is missing: %", fileName))
            return
        }

        var absolute = catch Path.absolute(fileName) as pathError
        if pathError != null
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke cannot resolve fixture path: %", fileName))
            return
        }

        if not .smokeOpened
        {
            .smokeOpened = true
            .queueFile(absolute, remember: false)
            return
        }

        if .currentFile != absolute
        {
            .waitForSmokeViewer(key, fileName)
            return
        }

        if not .smokeSelected
        {
            var selected = Swag.U32.Max
            for choice, index in .choices where choice.key == key
            {
                selected = cast(u32, index)
                break
            }

            if selected == Swag.U32.Max
            {
                .finishSmokeReview(1, Format.toString("Swag Scope smoke fixture '%' has no '%' viewer", fileName, key))
                return
            }

            if not .activateChoice(selected)
            {
                .waitForSmokeViewer(key, fileName)
                return
            }

            .smokeSelected  = true
            .smokeWaitSteps = 0
        }

        if .activeChoiceIndex >= .instances.count
        {
            .waitForSmokeViewer(key, fileName)
            return
        }

        let instance = &.instances[.activeChoiceIndex]
        if not instance.failureReason.isEmpty()
        {
            .finishSmokeReview(1, Format.toString("Swag Scope smoke viewer '%' cannot open '%': %", key, fileName, instance.failureReason))
            return
        }

        let loading  = instance.view and instance.isLoading and instance.isLoading()
        let blocking = loading and instance.needsLoadingOverlay and instance.needsLoadingOverlay()

        // Streaming text already has a presentable first chunk while it continues reading. Keep
        // it visible for a bounded interval so late errors cross the viewer contract; only a
        // viewer that says it has no presentable content (video before its first frame) blocks the
        // review until ready.
        if .smokeWaitSteps < SmokeMinimumSteps or (loading and (blocking or .smokeWaitSteps < SmokeExposureSteps))
        {
            .waitForSmokeViewer(key, fileName)
            return
        }

        Console.println("Swag Scope smoke reviewed '", key, "' with '", fixture, "'")
        .smokeSpecIndex += 1
        .smokeWaitSteps = 0
        .smokeOpened    = false
        .smokeSelected  = false
    }
}
