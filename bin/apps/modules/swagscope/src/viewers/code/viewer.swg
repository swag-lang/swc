#global internal

using Core, Pixel, Gui

private func codePluginProbe(content: Viewer.ProbeContent)->bool => not content.claimed and codeShebang(cast(string) content.head).found

// Describes the source-code viewer to the host.
//
// A file with no known extension is still offered the viewer when it opens with an interpreter
// line, which is how a script without a suffix names the language it is written in.
func codeViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "code"
        .staticName   = "Code"
        .attach       = &registerCodeStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Code
        .create       = &createCodeViewer
        .probe        = &codePluginProbe
        .textual      = true
        .smokeFixture = "sample.cpp"
        .addSelectors(".swg;.swgs;.c;.h;.cc;.cpp;.cxx;.hh;.hpp;.hxx;.inl;.ipp;.cs;.java;.js;.jsx;.mjs;.cjs;.ts;.tsx;.mts;.cts;.go;.rs;.py;.pyw;.pyi;.rb;.rake;.gemspec;.sh;.bash;.zsh;.fish;.ps1;.psm1;.psd1;.php;.phtml;.lua;.sql;.json;.jsonc;.json5;.xml;.xsd;.xsl;.xslt;.csproj;.vcxproj;.props;.targets;.css;.scss;.sass;.less;.yaml;.yml;.toml;.ini;.cfg;.conf;.properties;.kt;.kts;.swift;.dart;.r;.pl;.pm;.vb;.glsl;.vert;.frag;.geom;.comp;.hlsl;.fx;.cmake;.bat;.cmd;.htm;.html;.shtml;.xht;.xhtml;.asm;.s;.incasm;.zig;.nim;.nims;.nimble;.hs;.lhs;.scala;.sc;.groovy;.gvy;.gy;.gsh;.ex;.exs;.erl;.hrl;.clj;.cljs;.cljc;.edn;.jl;.f;.for;.f77;.f90;.f95;.f03;.f08;.pas;.pp;.lpr;.d;.di;.m;.mm;.tcl;.tk;.awk;.vim;.tex;.sty;.cls;.bib;.proto;.graphql;.gql;.gradle;.mk;.mak;.make;makefile;gnumakefile;bsdmakefile;.dockerfile;dockerfile;containerfile;cmakelists.txt;justfile;rakefile;gemfile;vagrantfile;podfile;brewfile;jenkinsfile;meson.build;.gitignore;.gitattributes;.gitmodules;.editorconfig;.clang-format;.clang-tidy;.prettierrc;.eslintrc;.npmrc;.yarnrc;.env;.nix")
    }

    return result
}

private const CodeStreamChunkSize = 16 * 1024'u64

// Viewport heights of text kept loaded from the top of the visible one: it and five more.
private const CodeStreamLookAhead    = 6.0
private const CodeResidentWindowSize = 256 * 1024'u64
private const CodeRevealContextSize  = 64 * 1024'u64

struct CodeViewer
{
    using wnd: Wnd

    late editor: *RichEditCtrl

    info:              *Wnd?
    zoomLabel:         *IconButton?
    zoomPercent:       u32 = 100
    swagLexer:         RichEditLexerSwag
    codeLexer:         GenericCodeLexer
    languageName:      String
    stream:            File.FileStream
    fileName:          String
    fileSize:          u64
    bytesRead:         u64
    residentStart:     u64
    residentOffsetY:   f32
    virtualHeight:     f32
    loadTimer:         *Timer?
    hasText:           bool
    pauseStreaming:    bool
    pendingSeek:       bool
    pendingSeekOffset: u64
    repositioning:     bool
    reportFailure:     Viewer.ReportFailure?
    failureReason:     String
}

impl CodeViewer
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

    mtd needsMore()->bool
    {
        if not .hasMore() do
            return false
        if .pauseStreaming do
            return false
        if .bytesRead - .residentStart >= CodeResidentWindowSize do
            return false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * CodeStreamLookAhead >= .residentOffsetY + loadedHeight
    }

    mtd updateEstimatedHeight()
    {
        let consumed = .bytesRead - .residentStart
        if not consumed do
            return
        if .bytesRead >= .fileSize and not .residentStart
        {
            .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        if loadedHeight <= 0
        {
            if .repositioning or not .residentStart do
                .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
            if .virtualHeight > 0 do
                .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            return
        }

        .virtualHeight = Math.max(.virtualHeight, loadedHeight * cast(f32) .fileSize / cast(f32) consumed, loadedHeight)
        if .repositioning or not .residentStart do
            .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
    }

    mtd scheduleMore()
    {
        if .loadTimer or (not .pendingSeek and not .needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        .stream.close()
    }

    mtd finishLoading()
    {
        .stream.close()
        .bytesRead = .fileSize
        if not .residentStart do
            .editor.setEstimatedDocumentHeight(0)
    }

    mtd showReadError(reason: string)
    {
        .stopLoading()
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = "source stream could not be read"
        .editor.setEstimatedDocumentHeight(0)
        if .hasText and .reportFailure do
            .reportFailure(me, .failureReason.toString())
    }

    mtd loadNextChunk()
    {
        if .bytesRead - .residentStart >= CodeResidentWindowSize do
            return
        if not .hasMore() do
            return

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readUtf8Chunk(CodeStreamChunkSize) as readError
        if readError != null
        {
            .showReadError(Errors.message(readError))
            return
        }

        if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .showReadError("source contains a zero byte and is not supported UTF-8 text")
            return
        }

        if chunk.isEmpty()
        {
            .finishLoading()
            return
        }

        .editor.addText(chunk.toString())
        let position = catch .stream.position() as positionError
        if positionError == null do
            .bytesRead = position
        .hasText = true
        .updateEstimatedHeight()
        .editor.setScrollPosition(oldPosition)
        if not .hasMore() do
            .finishLoading()
    }

    mtd revealOffset(offset: u64, text: string)->bool
    {
        .stopLoading()
        .pendingSeek   = false
        .repositioning = true
        defer .repositioning = false
        let requested = Math.min(offset, .fileSize)
        let start     = requested > CodeRevealContextSize ? requested - CodeRevealContextSize : 0
        for adjustment in 4
        {
            .stream = catch File.openReadLive(.fileName.toString()) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            let chunk = catch .stream.readUtf8Chunk(CodeResidentWindowSize) as readError
            if readError != null
            {
                .stream.close()
                continue
            }

            let previousHeight = Math.max(.virtualHeight, .editor.scrollableClientRect().height)
            .residentStart = actual
            .editor.setText(chunk.toString())
            let position = catch .stream.position() as positionError
            .bytesRead     = positionError == null ? position : actual + chunk.length
            .hasText       = not chunk.isEmpty()
            .virtualHeight = previousHeight
            .updateEstimatedHeight()
            if text.count do
                Viewer.highlightRichEditMatch(.editor, chunk.toString(), requested - actual, text.count)
            .scheduleMore()
            return true
        }

        return false
    }

    mtd setZoom(percent: u32)
    {
        .zoomPercent = Math.clamp(percent, 50'u32, 300'u32)
        let base = .themeMetrics().defaultFixedFontSize
        let size = cast(u32) Math.max(Math.round(cast(f32) base * cast(f32) .zoomPercent / 100), 1)
        .editor.style.setFont(.theme().createDefaultFontFs(size), .Regular)
        .editor.setFlags(.editor.flags)
        .zoomLabel?.setText(Format.toString("% %", .zoomPercent, "%"))
        .updateEstimatedHeight()
    }

    mtd showZoomMenu()
    {
        if not .zoomLabel do
            return
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.code.zoom75")
        menu.addItem("100%", "scope.code.zoom100")
        menu.addItem("125%", "scope.code.zoom125")
        menu.addItem("150%", "scope.code.zoom150")
        menu.addItem("200%", "scope.code.zoom200")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.code.zoom75":  .setZoom(75)
        case "scope.code.zoom100": .setZoom(100)
        case "scope.code.zoom125": .setZoom(125)
        case "scope.code.zoom150": .setZoom(150)
        case "scope.code.zoom200": .setZoom(200)
        }
    }

    // Creates the streamed, syntax-colored view of `fileName` under `contentParent`.
    //
    // `info` receives the zoom control when the view is hosted with an information group, and
    // `reportFailure` hears about read errors discovered once text is already shown.
    func create(contentParent: *Wnd, fileName: string, reportFailure: Viewer.ReportFailure? = null, info: *Wnd? = null)->*CodeViewer
    {
        with let result = Wnd.create'CodeViewer(contentParent, "scope.code")
        {
            .backgroundStyle = .View
            .fileName        = fileName
            .reportFailure   = reportFailure
            .info            = info
        }

        result.createEditor()
        if info do
            result.createZoomControl(info)
        result.selectLexer()
        result.hookEvents()
        result.startReading()

        result.applyLayout()
        result.setZoom(100)
        result.scheduleMore()
        result.setInitialFocus(result.editor)
        return result
    }

    // Decides whether scrolling from `oldPosition` to `newPosition` leaves the resident window,
    // and asks for the part of the file it reaches when it does.
    mtd followScroll(oldPosition, newPosition: Math.Point)
    {
        if .repositioning do
            return
        if .pauseStreaming and newPosition.y < oldPosition.y do
            .pauseStreaming = false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()

        let residentHeight = loadedHeight > 0 ? loadedHeight : (.fileSize ? .virtualHeight * cast(f32) (.bytesRead - .residentStart) / cast(f32) .fileSize : 0)
        let residentEnd    = .residentOffsetY + residentHeight
        let before         = .residentStart > 0 and newPosition.y < oldPosition.y and newPosition.y < .residentOffsetY + viewport.height * CodeStreamLookAhead
        let after          = .hasMore() and .bytesRead - .residentStart >= CodeResidentWindowSize and newPosition.y > oldPosition.y and newPosition.y + viewport.height * CodeStreamLookAhead > residentEnd
        let outside        = newPosition.y < .residentOffsetY or newPosition.y + viewport.height > residentEnd
        .pendingSeek = .virtualHeight > 0 and (before or after or outside)
        if .pendingSeek
        {
            let ratio = Math.clamp(newPosition.y / .virtualHeight, 0, 1)
            .pendingSeekOffset = cast(u64) (ratio * cast(f32) .fileSize)

            // A continuous gesture must have its bytes before the next paint, even when
            // the timer was delayed. Ordinary prefetch still runs on the short timer.
            if outside and Math.abs(newPosition.y - oldPosition.y) <= viewport.height
            {
                if not before and not after and .needsMore()
                {
                    .pendingSeek = false
                    .loadNextChunk()
                }
                else do
                    discard .revealOffset(.pendingSeekOffset, "")
            }
        }

        .scheduleMore()
    }

    // Creates the read-only editor that shows the resident window of the file.
    private mtd createEditor()
    {
        with .editor = RichEditCtrl.create(me)
        {
            .dockStyle   = .Center
            .marginLeft  = 12
            .marginRight = 12
            .style.setFont(me.theme().createDefaultFontFs(me.themeMetrics().defaultFixedFontSize), .Regular)
            .setFlags(.ReadOnly)
        }
    }

    // Creates the zoom menu button in the host's information group `info`.
    private mtd createZoomControl(info: *Wnd)
    {
        with .zoomLabel = IconButton.create(info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.code.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = codeStrings().ui_ZoomMenu
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }
    }

    // Colors the editor with the Swag lexer for Swag sources, and with the generic lexer configured
    // for the file's language otherwise.
    private mtd selectLexer()
    {
        let extension = Path.lowercaseExtension(.fileName.toString())
        if extension == ".swg" or extension == ".swgs"
        {
            .languageName = "Swag"
            .editor.setLexer(&.swagLexer)
        }
        else
        {
            let language = codeLanguage(.fileName.toString())
            .languageName = codeLanguageName(language)
            .codeLexer.configure(language)
            .editor.setLexer(&.codeLexer)
        }
    }

    // Follows scrolling with the resident window, routes the keys the code view answers for, and
    // keeps painting and resizing from reloading text.
    private mtd hookEvents()
    {
        .editor.sigScrollPositionChanged += func|view = me|(editor, oldPosition, newPosition)
        {
            discard editor
            view.followScroll(oldPosition, newPosition)
        }

        .hookOnChildEvent = func|view = me|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case PaintEvent as paintEvt:

                // Caret placement and wrapping publish scroll corrections during paint. They
                // must not reload the text whose lines the renderer is currently traversing.
                let previous = view.repositioning
                view.repositioning = true
                defer view.repositioning = previous
                paintEvt.target!.processEvent(evt)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Add or keyEvt.key == .OemPlus) and keyEvt.modifiers.has(.Control):
                view.setZoom(view.zoomPercent + 25)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Subtract or keyEvt.key == .OemMinus) and keyEvt.modifiers.has(.Control):
                view.setZoom(view.zoomPercent > 50 ? view.zoomPercent - 25 : 50)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .D0 and keyEvt.modifiers.has(.Control):
                view.setZoom(100)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize, "")
                view.repositioning = true
                view.editor.keyPressed(.End, .Control)
                view.repositioning = false
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Home and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.repositioning = true
                view.editor.keyPressed(.Home, .Control)
                view.repositioning = false
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown or keyEvt.key == .Space):
                view.pauseStreaming = false
                view.scheduleMore()
                return false

            default:
                return false
            }
        }

        .hookOnEvent = func|view = me|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent
            {
                view.updateEstimatedHeight()
                view.scheduleMore()
            }

            return false
        }
    }

    // Opens the source stream and reads its first chunk, or records why it cannot be read.
    private mtd startReading()
    {
        .stream = catch File.openReadLive(.fileName.toString()) as openError
        if openError != null
        {
            .showReadError(Errors.message(openError))
            return
        }

        let size = catch .stream.size() as sizeError
        if sizeError != null
        {
            .showReadError(Errors.message(sizeError))
            return
        }

        .fileSize = size
        if not size do
            .finishLoading()
        else do
            .loadNextChunk()
    }
}

impl IWnd for CodeViewer
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        discard evt
        if .pendingSeek do
            discard .revealOffset(.pendingSeekOffset, "")
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .zoomLabel do
            .zoomLabel.toolTip = codeStrings().ui_ZoomMenu
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopLoading()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .loadTimer = null
        if .pendingSeek
        {
            let offset = .pendingSeekOffset
            .pendingSeek = false
            discard .revealOffset(offset, "")
            return
        }

        .updateEstimatedHeight()
        if .needsMore() do
            .loadNextChunk()
        .scheduleMore()
    }
}

// Creates the integrated syntax-colored source view.
func createCodeViewer(host: Viewer.Host)
{
    let view = CodeViewer.create(host.contentParent(), host.fileName(), host.services().reportFailure, host.createInfoGroup(ViewerZoomSlotWidth))
    if not view.failureReason.isEmpty()
    {
        host.reject(view.failureReason.toString())
        view.destroy()
        return
    }

    host.attachView(view)
    host.setDetails(Format.toString(codeStrings().ui_Details, view.languageName).toString())
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool => (cast #assume (*CodeViewer) wnd).revealOffset(match.offset, text),
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return Viewer.richEditMatchBounds((cast #assume (*CodeViewer) wnd).editor, bounds)
    },
        clear: func(wnd) { Viewer.clearRichEditMatch((cast #assume (*CodeViewer) wnd).editor) }})
    host.setLifecycle({isLoading: func(wnd)->bool => (cast #assume (*CodeViewer) wnd).loadTimer != null})
}
