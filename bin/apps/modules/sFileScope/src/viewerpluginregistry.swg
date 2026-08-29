using Core, Core.Errors, Gui, Audio, Pixel, Video

// Stable identity and smoke input of the built-in text plugin.
const BasicTextViewerKey    = "text"
const BasicTextSmokeFixture = "comprehensive.txt"

// What the text surface owns by name.
//
// Which viewer a file is offered is still decided by reading it, since a file with no
// extension at all can be text and one that ends in `.dat` can be anything. This list is what
// a row of the file panel can say without opening the file it names, and a plain text file
// says it plainly enough.
private const TextNamedExtensions = ".txt;.text;.log;.nfo;.diz;.rst;.adoc;.asc;.srt;.vtt;.sub;.ssa;.ass;.lrc;.diff;.patch;readme;license;licence;changelog;authors;copying;install;news;todo"

// One plugin offered for the current file.
struct ViewerPluginChoice
{
    pluginIndex: u64        // Index in [[ViewerPluginRegistry.plugins]].
    key:         String     // Stable identity copied from the plugin descriptor.
}

// Viewer plugins available to sFileScope, in selection order.
struct ViewerPluginRegistry
{
    plugins: Array'FileScope.Plugin
}

private func builtInPluginIcon(parent: *Wnd, size: f32, data: u64)->Icon
{
    return (cast(*ViewerWindow) parent).icon(cast(ViewerIcons) data, size)
}

private func basicTextPluginName()->string => appStrings().ui_BasicText

private func basicTextPluginProbe(fileName: string, hasNamedMatch: bool)->bool
{
    discard hasNamedMatch
    return BasicTextView.supports(fileName)
}

private func codePluginProbe(fileName: string, hasNamedMatch: bool)->bool
{
    return !hasNamedMatch and codeShebang(fileName).found
}

private func addPlugin(registry: *ViewerPluginRegistry, key, name: string, icon: ViewerIcons, create: FileScope.PluginCreate, smokeFixture, selectors: string, matchNames = true, probe: #null FileScope.PluginProbe = null, resolveName: #null FileScope.PluginName = null)
{
    var plugin: FileScope.Plugin
    plugin.key          = key
    plugin.staticName   = name
    plugin.icon         = &builtInPluginIcon
    plugin.iconData     = cast(u64) icon
    plugin.create       = create
    plugin.probe        = probe
    plugin.resolveName  = resolveName
    plugin.matchNames   = matchNames
    plugin.smokeFixture = smokeFixture
    for selector in Tokenize.split(selectors, ';'u8) do
        plugin.selectors.add(String.from(selector))
    expect registry.register(#move plugin)
}

private func addPlugin(registry: *ViewerPluginRegistry, key, name: string, icon: ViewerIcons, create: FileScope.PluginCreate, smokeFixture: string, selectors: const [..] String, matchNames = true, probe: #null FileScope.PluginProbe = null, resolveName: #null FileScope.PluginName = null)
{
    var plugin: FileScope.Plugin
    plugin.key          = key
    plugin.staticName   = name
    plugin.icon         = &builtInPluginIcon
    plugin.iconData     = cast(u64) icon
    plugin.create       = create
    plugin.probe        = probe
    plugin.resolveName  = resolveName
    plugin.matchNames   = matchNames
    plugin.smokeFixture = smokeFixture
    for selector in selectors do
        plugin.selectors.add(String.from(selector.toString()))
    expect registry.register(#move plugin)
}

// Creates the complete built-in plugin registry.
func createViewerPluginRegistry()->ViewerPluginRegistry
{
    var result: retval
    addPlugin(&result, "html", "HTML", .Html, &createHtmlViewer, "viewer.html", ".htm;.html;.shtml;.xht;.xhtml")
    addPlugin(&result, "code", "Code", .Code, &createCodeViewer, "sample.cpp", ".swg;.swgs;.c;.h;.cc;.cpp;.cxx;.hh;.hpp;.hxx;.inl;.ipp;.cs;.java;.js;.jsx;.mjs;.cjs;.ts;.tsx;.mts;.cts;.go;.rs;.py;.pyw;.pyi;.rb;.rake;.gemspec;.sh;.bash;.zsh;.fish;.ps1;.psm1;.psd1;.php;.phtml;.lua;.sql;.json;.jsonc;.json5;.xml;.xsd;.xsl;.xslt;.csproj;.vcxproj;.props;.targets;.css;.scss;.sass;.less;.yaml;.yml;.toml;.ini;.cfg;.conf;.properties;.kt;.kts;.swift;.dart;.r;.pl;.pm;.vb;.glsl;.vert;.frag;.geom;.comp;.hlsl;.fx;.cmake;.bat;.cmd;.htm;.html;.shtml;.xht;.xhtml;.asm;.s;.incasm;.zig;.nim;.nims;.nimble;.hs;.lhs;.scala;.sc;.groovy;.gvy;.gy;.gsh;.ex;.exs;.erl;.hrl;.clj;.cljs;.cljc;.edn;.jl;.f;.for;.f77;.f90;.f95;.f03;.f08;.pas;.pp;.lpr;.d;.di;.m;.mm;.tcl;.tk;.awk;.vim;.tex;.sty;.cls;.bib;.proto;.graphql;.gql;.gradle;.mk;.mak;.make;makefile;gnumakefile;bsdmakefile;.dockerfile;dockerfile;containerfile;cmakelists.txt;justfile;rakefile;gemfile;vagrantfile;podfile;brewfile;jenkinsfile;meson.build;.gitignore;.gitattributes;.gitmodules;.editorconfig;.clang-format;.clang-tidy;.prettierrc;.eslintrc;.npmrc;.yarnrc;.env;.nix", probe: &codePluginProbe)
    addPlugin(&result, "markdown", "Markdown", .Markdown, &createMarkdownViewer, "comprehensive.md", ".markdown;.md;.mdown;.mdwn;.mkd;.mkdn;.rmd")
    addPlugin(&result, "subtitle", "Subtitles", .Subtitle, &createSubtitleViewer, "viewer.srt", ".srt;.vtt;.ass;.ssa;.lrc;.sub")

    var imageExtensions: Array'String
    let imageFormats = Image.decodableFormats()
    for format in imageFormats
    {
        for extension in Tokenize.split(format.extensions, ';'u8) do
            imageExtensions.add(String.from(extension))
    }

    imageExtensions.add(String.from(".svg"))
    addPlugin(&result, "image", "Image", .Image, &createImageViewer, "sample.svg", imageExtensions.toSlice())

    var videoExtensions: Array'String
    let videoFormats = Reader.decodableFormats()
    for format in videoFormats
    {
        for extension in Tokenize.split(format.extensions, ';'u8) do
            videoExtensions.add(String.from(extension))
    }

    addPlugin(&result, "video", "Video", .Video, &createVideoViewer, "glint-aac-mjpeg.mp4", videoExtensions.toSlice())
    addPlugin(&result, "pdf", "PDF", .Pdf, &createPdfViewer, "viewer.pdf", ".pdf")
    let soundExtensions = SoundFile.decodableExtensions()
    addPlugin(&result, "sound", "Sound", .Sound, &createSoundViewer, "pacman_beginning.wav", soundExtensions.toSlice())
    addPlugin(&result, "font", "Font", .Font, &createFontViewer, "segoeui.ttf", ".ttf;.ttc")
    addPlugin(&result, "midi", "MIDI", .Midi, &createMidiViewer, "viewer.mid", ".mid;.midi")
    addPlugin(&result, "table", "Table", .Table, &createTableViewer, "viewer.csv", ".csv;.tsv;.tab")
    addPlugin(&result, BasicTextViewerKey, "", .Text, &createBasicTextViewer, BasicTextSmokeFixture, TextNamedExtensions, matchNames: false, probe: &basicTextPluginProbe, resolveName: &basicTextPluginName)
    addPlugin(&result, "binary", "Binary", .Binary, &createBinaryViewer, "appicon.ico", ".exe;.dll;.sys;.ocx;.cpl;.scr;.efi;.drv;.mui;.mun;.winmd;.node;.pyd;.obj;.o;.lib;.a;.so;.elf;.ko;.axf;.dylib;.bundle;.wasm;.scc;.zip;.jar;.war;.apk;.aar;.epub;.whl;.nupkg;.vsix;.crx;.xpi;.docx;.xlsx;.pptx;.odt;.ods;.odp;.otf;.woff;.woff2;.ico;.cur;.gz;.tgz;.bz2;.tbz2;.xz;.txz;.zst;.tzst;.7z;.rar;.cab;.msi;.doc;.xls;.ppt;.ps;.eps;.class;.dex;.sqlite;.db;.pdb;.mid;.midi;.wav;.avi;.webp;.mp3;.flac;.ogg;.oga;.ogv;.mp4;.m4a;.m4v;.mov;.3gp;.3g2;.mkv;.webm;*")
    addPlugin(&result, "hex", "Hexadecimal", .Hex, &createHexViewer, "viewer.hex", "*")
    return result
}

impl ViewerPluginRegistry
{
    private mtd const matches(plugin: const *FileScope.Plugin, baseName, extension: string, wildcard: bool)->bool
    {
        for supported in plugin.selectors
        {
            if wildcard and supported[] == "*" do
                return true
            if wildcard do
                continue

            let selector = supported[].toString()
            if selector[0] == '.'
            {
                if selector == extension do
                    return true
            }
            elif selector == baseName do
                return true
        }

        return false
    }

    // Registers one plugin after validating the host-facing contract.
    mtd register(plugin: FileScope.Plugin) fail
    {
        if plugin.apiVersion != FileScope.ViewerApiVersion do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' uses API version %, host needs %", plugin.key, plugin.apiVersion, FileScope.ViewerApiVersion).toString())}
        if plugin.key.isEmpty() do
            fail InvalidFormatError{"viewer plugin key is missing"}
        if plugin.key != plugin.key.toLower() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is not lowercase", plugin.key).toString())}
        if plugin.staticName.isEmpty() and !plugin.resolveName do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no display name", plugin.key).toString())}
        if plugin.icon == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no icon provider", plugin.key).toString())}
        if plugin.create == null do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no creation callback", plugin.key).toString())}
        if plugin.smokeFixture.isEmpty() or (Path.fileName(plugin.smokeFixture.toString()) orelse "") != plugin.smokeFixture.toString() do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' needs one smoke-fixture basename", plugin.key).toString())}
        if plugin.selectors.isEmpty() and !plugin.probe do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin '%' has no selector or content probe", plugin.key).toString())}
        for current in .plugins where current.key == plugin.key do
            fail InvalidFormatError{Errors.mkString(Format.toString("viewer plugin key '%' is already registered", plugin.key).toString())}
        .plugins.add(#move plugin)
    }

    // Returns the plugin that stands for `fileName`, from its name alone.
    //
    // A list of files decorates a row per file, and reading the beginning of a file to decide
    // what it holds costs one open per row. That is invisible on a local disk and thirty
    // milliseconds a file across a network share, where a folder of six hundred films takes
    // twenty seconds of it before anything else in the window moves. A row therefore reads its
    // glyph from the name, which is what names are for; only the file a reader actually opens
    // is worth looking inside.
    mtd const namePlugin(fileName: string, pluginIndex: *u64)->bool
    {
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()

        for plugin, index in .plugins where .matches(plugin, baseName.toString(), extension.toString(), wildcard: false)
        {
            pluginIndex[] = index
            return true
        }

        for plugin, index in .plugins where .matches(plugin, baseName.toString(), extension.toString(), wildcard: true)
        {
            pluginIndex[] = index
            return true
        }

        return false
    }

    // Returns every viewer available for `fileName` in selection order.
    mtd const choices(fileName: string)->Array'ViewerPluginChoice
    {
        var result:  retval
        var matched: Array'bool
        matched.resize(.plugins.count)
        var hasNamedMatch: bool
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()

        for plugin, index in .plugins where plugin.matchNames and .matches(plugin, baseName.toString(), extension.toString(), wildcard: false)
        {
            result.add({index, plugin.key})
            matched[index] = true
            hasNamedMatch  = true
        }

        for plugin, index in .plugins where !matched[index] and plugin.probe and plugin.probe!(fileName, hasNamedMatch)
        {
            result.add({index, plugin.key})
            matched[index] = true
        }

        for plugin, index in .plugins where !matched[index] and .matches(plugin, baseName.toString(), extension.toString(), wildcard: true) do
            result.add({index, plugin.key})
        return result
    }

    // Reports whether two files share one explicitly registered viewer, or the same extension
    // when neither has a format-specific viewer.
    mtd const sharesViewer(a, b: string)->bool
    {
        var extensionA = String.from(Path.extension(a) orelse "")
        extensionA = extensionA.toLower()
        var extensionB = String.from(Path.extension(b) orelse "")
        extensionB = extensionB.toLower()
        var baseA = String.from(Path.fileName(a) orelse "")
        baseA = baseA.toLower()
        var baseB = String.from(Path.fileName(b) orelse "")
        baseB = baseB.toLower()

        var anyA, anyB: bool
        for plugin in .plugins where plugin.matchNames
        {
            let matchA = .matches(plugin, baseA.toString(), extensionA.toString(), wildcard: false)
            let matchB = .matches(plugin, baseB.toString(), extensionB.toString(), wildcard: false)
            if matchA and matchB do
                return true
            anyA = anyA or matchA
            anyB = anyB or matchB
        }

        if !anyA and !anyB do
            return extensionA == extensionB
        return false
    }

    // Reports whether `fileName` has an explicitly registered extension or exact name.
    mtd const explicitlySupports(fileName: string)->bool
    {
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()
        for plugin in .plugins where plugin.matchNames
        {
            for supported in plugin.selectors
            {
                let selector = supported[].toString()
                if selector == "*" do
                    continue
                if selector[0] == '.' and selector == extension.toString() do
                    return true
                if selector[0] != '.' and selector == baseName.toString() do
                    return true
            }
        }

        return false
    }
}

impl FileScope.Plugin
{
    // Creates one selected plugin and verifies the common session contract.
    mtd createView(host: FileScope.Host, session: *ViewerSession) fail
    {
        .create(host)
        if session.view and !session.failureReason.isEmpty() do
            fail InvalidFormatError{"viewer plugin returned both a document view and a rejection reason"}
        if !session.view and session.failureReason.isEmpty() do
            fail InvalidFormatError{"viewer plugin returned neither a document view nor a rejection reason"}
        if !session.view and (session.actions or session.info or session.commands) do
            fail InvalidFormatError{"viewer plugin returned chrome without a document view"}
    }
}
