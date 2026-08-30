#global internal

using Core, Pixel, Gui

private func codePluginProbe(fileName: string, hasNamedMatch: bool)->bool
{
    return !hasNamedMatch and codeShebang(fileName).found
}

// Describes the source-code viewer to the host.
//
// A file with no known extension is still offered the viewer when it opens with an interpreter
// line, which is how a script without a suffix names the language it is written in.
func codeViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "code"
    result.staticName   = "Code"
    result.attach       = &registerCodeStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Code
    result.create       = &createCodeViewer
    result.probe        = &codePluginProbe
    result.smokeFixture = "sample.cpp"
    result.addSelectors(".swg;.swgs;.c;.h;.cc;.cpp;.cxx;.hh;.hpp;.hxx;.inl;.ipp;.cs;.java;.js;.jsx;.mjs;.cjs;.ts;.tsx;.mts;.cts;.go;.rs;.py;.pyw;.pyi;.rb;.rake;.gemspec;.sh;.bash;.zsh;.fish;.ps1;.psm1;.psd1;.php;.phtml;.lua;.sql;.json;.jsonc;.json5;.xml;.xsd;.xsl;.xslt;.csproj;.vcxproj;.props;.targets;.css;.scss;.sass;.less;.yaml;.yml;.toml;.ini;.cfg;.conf;.properties;.kt;.kts;.swift;.dart;.r;.pl;.pm;.vb;.glsl;.vert;.frag;.geom;.comp;.hlsl;.fx;.cmake;.bat;.cmd;.htm;.html;.shtml;.xht;.xhtml;.asm;.s;.incasm;.zig;.nim;.nims;.nimble;.hs;.lhs;.scala;.sc;.groovy;.gvy;.gy;.gsh;.ex;.exs;.erl;.hrl;.clj;.cljs;.cljc;.edn;.jl;.f;.for;.f77;.f90;.f95;.f03;.f08;.pas;.pp;.lpr;.d;.di;.m;.mm;.tcl;.tk;.awk;.vim;.tex;.sty;.cls;.bib;.proto;.graphql;.gql;.gradle;.mk;.mak;.make;makefile;gnumakefile;bsdmakefile;.dockerfile;dockerfile;containerfile;cmakelists.txt;justfile;rakefile;gemfile;vagrantfile;podfile;brewfile;jenkinsfile;meson.build;.gitignore;.gitattributes;.gitmodules;.editorconfig;.clang-format;.clang-tidy;.prettierrc;.eslintrc;.npmrc;.yarnrc;.env;.nix")
    return result
}

private const CodeStreamChunkSize    = 16 * 1024'u64
private const CodeStreamLookAhead    = 2.0
private const CodeResidentWindowSize = 256 * 1024'u64
private const CodeRevealContextSize  = 4 * 1024'u64

internal struct CodeViewer
{
    using wnd: Wnd

    #[Swag.Late]
    editor: *RichEditCtrl

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
    loadTimer:         #null *Timer
    hasText:           bool
    pauseStreaming:    bool
    pendingSeek:       bool
    pendingSeekOffset: u64
    repositioning:     bool
    reportFailure:     #null Viewer.ReportFailure
    failureReason:     String
}

internal impl CodeViewer
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

    mtd needsMore()->bool
    {
        if !.hasMore() do
            return false
        if .pauseStreaming do
            return false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * CodeStreamLookAhead >= .residentOffsetY + loadedHeight
    }

    mtd updateEstimatedHeight()
    {
        let consumed = .bytesRead - .residentStart
        if !consumed do
            return
        if .bytesRead >= .fileSize and !.residentStart
        {
            .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        if loadedHeight <= 0 do
            return
        .virtualHeight   = Math.max(.virtualHeight, loadedHeight * cast(f32) .fileSize / cast(f32) consumed, loadedHeight)
        .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
    }

    mtd scheduleMore()
    {
        if .loadTimer or (!.pendingSeek and !.needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        .stream.close()
    }

    mtd finishLoading()
    {
        .stream.close()
        .bytesRead = .fileSize
        if !.residentStart do
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
            .reportFailure!(me, .failureReason.toString())
    }

    mtd loadNextChunk()
    {
        if !.hasMore() do
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
        if !.hasMore() do
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
            .stream = catch File.openRead(.fileName.toString()) as openError
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
            .hasText       = !chunk.isEmpty()
            .virtualHeight = previousHeight
            .updateEstimatedHeight()
            if text.count do
                Viewer.highlightRichEditMatch(.editor, chunk.toString(), requested - actual, text.count)
            .scheduleMore()
            return true
        }

        return false
    }

    func create(contentParent: *Wnd, fileName: string, reportFailure: #null Viewer.ReportFailure = null)->*CodeViewer
    {
        let result = Wnd.create'CodeViewer(contentParent, "scope.code")
        result.backgroundStyle = .View
        result.fileName        = fileName
        result.reportFailure   = reportFailure

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.editor.setFlags(.ReadOnly)
        let extension = Path.lowercaseExtension(fileName)
        if extension == ".swg" or extension == ".swgs"
        {
            result.languageName = "Swag"
            result.editor.setLexer(&result.swagLexer)
        }
        else
        {
            let language = codeLanguage(fileName)
            result.languageName = codeLanguageName(language)
            result.codeLexer.configure(language)
            result.editor.setLexer(&result.codeLexer)
        }

        result.editor.sigScrollPositionChanged += func|view = result|(editor, oldPosition, newPosition)
        {
            discard editor
            if view.repositioning do
                return
            if view.pauseStreaming and newPosition.y < oldPosition.y do
                view.pauseStreaming = false
            let loadedHeight = view.editor.loadedDocumentHeight()
            if loadedHeight > 0 and view.virtualHeight > 0 and (newPosition.y + view.editor.paddedClientRect().height < view.residentOffsetY or newPosition.y > view.residentOffsetY + loadedHeight)
            {
                let ratio = Math.clamp(newPosition.y / view.virtualHeight, 0, 1)
                view.pendingSeekOffset = cast(u64) (ratio * cast(f32) view.fileSize)
                view.pendingSeek       = true
            }

            view.scheduleMore()
        }
        result.hookOnChildEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize > CodeResidentWindowSize ? view.fileSize - CodeResidentWindowSize : 0, "")
                view.editor.keyPressed(.End, .Control)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Home and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.editor.keyPressed(.Home, .Control)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown or keyEvt.key == .Space):
                view.pauseStreaming = false
                view.scheduleMore()
                return false

            default:
                return false
            }
        }
        result.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent
            {
                view.updateEstimatedHeight()
                view.scheduleMore()
            }

            return false
        }

        result.stream = catch File.openRead(fileName) as openError
        if openError != null do
            result.showReadError(Errors.message(openError))
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError != null do
                result.showReadError(Errors.message(sizeError))
            else
            {
                result.fileSize = size
                if !size do
                    result.finishLoading()
                else do
                    result.loadNextChunk()
            }
        }

        result.applyLayout()
        result.scheduleMore()
        result.setInitialFocus(result.editor)
        return result
    }
}

internal impl IWnd for CodeViewer
{
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
    let view = CodeViewer.create(host.contentParent(), host.fileName(), host.services().reportFailure)
    if !view.failureReason.isEmpty()
    {
        host.reject(view.failureReason.toString())
        view.destroy()
        return
    }

    host.attachView(view)
    host.setDetails(Format.toString(codeStrings().ui_Details, view.languageName).toString())
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool { return (cast(*CodeViewer) wnd).revealOffset(match.offset, text) },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return Viewer.richEditMatchBounds((cast(*CodeViewer) wnd).editor, bounds)
    },
        clear: func(wnd) { Viewer.clearRichEditMatch((cast(*CodeViewer) wnd).editor) }})
    host.setLifecycle({isLoading: func(wnd)->bool { return (cast(*CodeViewer) wnd).loadTimer != null }})
}
