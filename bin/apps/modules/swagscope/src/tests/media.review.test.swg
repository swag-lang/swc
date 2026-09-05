#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Pixel, Gui

#test
{
    for palette in 3
    {
        for language in [ReferenceLanguage, "fr"]
        {
            var host: Testing.HeadlessHost
            host.setup(960, 540)
            defer
            {
                discard catch host.app.setLanguage(ReferenceLanguage)
                host.shutdown()
            }
            switch palette
            {
            case 0: host.theme.setSwagDark()
            case 1: host.theme.setDark()
            case 2: host.theme.setLight()
            }
            host.notify(.ThemeChanged)
            var session = openTestViewer(testViewerPlugin(func(viewerHost)
            {
                let panel = MediaInfoPanel.create(viewerHost)
                var data: MediaInfoData
                data.add(.Image, group: true)
                data.add(.Format, "JPEG")
                data.add(.Dimensions, "3840 × 2160 px")
                data.add(.DisplaySize, "3840 × 2160 px")
                data.add(.PixelFormat, "RGB8")
                data.add(.Depth, "24")
                data.add(.FrameRate, "25 fps")
                data.add(.Metadata, group: true)
                data.addText("Make", "Camera manufacturer")
                data.addText("Model", "Camera model")
                data.addText("DateTimeOriginal", "2026:09:05 14:30:00")
                data.addText("ExposureTime", "1/125")
                data.add(.Audio, "1", group: true)
                data.add(.SampleRate, "48000 Hz")
                data.add(.Channels, "2")
                panel.publish(&data)
                viewerHost.attachView(Wnd.create'Wnd(viewerHost.contentParent()))
            }), &host.root, "review")
            session.view!.dockStyle = .Center
            expect host.app.setLanguage(language)
            host.notify(.LanguageChanged)
            session.sidePanelButton!.setChecked(true)
            session.sidePanelButton!.sigCheckedChanged.call(session.sidePanelButton!)
            host.root.applyLayout()
            host.settleAnimations(&host.root, 4)
            Testing.assertContentFits(&host.root)
            var image = host.render(&host.root)
            let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("scope-media-review-%-%.png", palette, language).toString())
            expect image.save(path.toString())
            Console.println(path)
        }
    }
}
