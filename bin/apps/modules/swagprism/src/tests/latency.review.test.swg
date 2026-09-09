#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
    for example in [ExampleKind.Plasma, ExampleKind.Gui]
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        defer host.shutdown()
        window.panels[0].optimCombo.setSelectedIndex(2, notify: false)
        window.panels[0].selectViewer(exampleViewer(example))
        let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
        for sample in 3
        {
            let source = Format.toString("%\n// edit %\n", exampleSource(example), sample)
            var watch: Time.Stopwatch
            watch.start()
            viewer.compileSource(source.toString())
            while (viewer.queued or !viewer.frameCount) and viewer.running and watch.elapsedMilliseconds() < 90000
            {
                Threading.Thread.sleep(1'ms)
                viewer.poll()
            }

            if viewer.probe.failed do
                Console.print(viewer.probe.diagnostics.toString())
            Swag.assert(viewer.frameCount != 0 and !viewer.queued)
            Console.println("PRISM_EDIT kind=", cast(u32) example, " sample=", sample, " total_ms=", watch.elapsedMilliseconds(), " build_ms=", viewer.probe.compileMs, " frame_us=", viewer.renderUs)
        }

        window.shutdown()
    }
}
