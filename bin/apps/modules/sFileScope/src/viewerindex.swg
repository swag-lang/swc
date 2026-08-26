using Core, Core.Errors, Gui, Audio, Pixel, Video

// The stable identity of the host's own text surface, in the persisted vocabulary its
// registered neighbours use.
const BasicTextViewerKey = "text"

// One integrated viewer associated with lowercase extensions, exact file names, or every file.
struct ViewerSpec
{
    // Stable identity of the viewer, written into the persisted state. It is the name a reader's
    // viewer choice is remembered under, so it outlives the display name and the registration
    // order and is never translated.
    key: String

    displayName: String          // Name shown in the viewer selector.
    icon:        ViewerIcons     // Glyph shown beside that name.
    create:      ViewerCreate = undefined
    extensions:  Array'String     // Lowercase extensions or file names, or `*` for every file.
}

// Selects whether one available viewer is the basic text surface or a format-specific viewer.
enum ViewerChoiceKind
{
    BasicText
    Viewer
}

// One viewer offered for the current file.
struct ViewerChoice
{
    kind:      ViewerChoiceKind
    specIndex: u64 = Swag.U64.Max     // Index in [[ViewerIndex.specs]] for a format-specific viewer.
    key:       String                 // Stable identity of the viewer, as [[ViewerSpec.key]] defines it.
    name:      String                 // Name shown in the action-bar selector.
    icon:      ViewerIcons            // Glyph shown beside that name.
}

// The format viewers compiled into sFileScope, in selection order.
struct ViewerIndex
{
    specs: Array'ViewerSpec
}

private func addViewer(index: *ViewerIndex, key, name: string, icon: ViewerIcons, create: ViewerCreate, selectors: string)
{
    var spec: ViewerSpec
    spec.key         = String.from(key)
    spec.displayName = String.from(name)
    spec.icon        = icon
    spec.create      = create
    for selector in Tokenize.split(selectors, ';'u8) do
        spec.extensions.add(String.from(selector))
    index.specs.add(#move spec)
}

private func addViewer(index: *ViewerIndex, key, name: string, icon: ViewerIcons, create: ViewerCreate, selectors: const [..] String)
{
    var spec: ViewerSpec
    spec.key         = String.from(key)
    spec.displayName = String.from(name)
    spec.icon        = icon
    spec.create      = create
    for selector in selectors do
        spec.extensions.add(String.from(selector.toString()))
    index.specs.add(#move spec)
}

// Creates the complete built-in viewer table.
func createViewerIndex()->ViewerIndex
{
    var result: retval
    addViewer(&result, "html", "HTML", .Html, &createHtmlViewer, ".htm;.html;.shtml;.xht;.xhtml")
    addViewer(&result, "code", "Code", .Code, &createCodeViewer, ".swg;.swgs;.c;.h;.cc;.cpp;.cxx;.hh;.hpp;.hxx;.inl;.ipp;.cs;.java;.js;.jsx;.mjs;.cjs;.ts;.tsx;.mts;.cts;.go;.rs;.py;.pyw;.pyi;.rb;.rake;.gemspec;.sh;.bash;.zsh;.fish;.ps1;.psm1;.psd1;.php;.phtml;.lua;.sql;.json;.jsonc;.json5;.xml;.xsd;.xsl;.xslt;.csproj;.vcxproj;.props;.targets;.css;.scss;.sass;.less;.yaml;.yml;.toml;.ini;.cfg;.conf;.properties;.kt;.kts;.swift;.dart;.r;.pl;.pm;.vb;.glsl;.vert;.frag;.geom;.comp;.hlsl;.fx;.cmake;.bat;.cmd;.htm;.html;.shtml;.xht;.xhtml;.asm;.s;.incasm;.zig;.nim;.nims;.nimble;.hs;.lhs;.scala;.sc;.groovy;.gvy;.gy;.gsh;.ex;.exs;.erl;.hrl;.clj;.cljs;.cljc;.edn;.jl;.f;.for;.f77;.f90;.f95;.f03;.f08;.pas;.pp;.lpr;.d;.di;.m;.mm;.tcl;.tk;.awk;.vim;.tex;.sty;.cls;.bib;.proto;.graphql;.gql;.gradle;.mk;.mak;.make;makefile;gnumakefile;bsdmakefile;.dockerfile;dockerfile;containerfile;cmakelists.txt;justfile;rakefile;gemfile;vagrantfile;podfile;brewfile;jenkinsfile;meson.build;.gitignore;.gitattributes;.gitmodules;.editorconfig;.clang-format;.clang-tidy;.prettierrc;.eslintrc;.npmrc;.yarnrc;.env;.nix")
    addViewer(&result, "markdown", "Markdown", .Markdown, &createMarkdownViewer, ".markdown;.md;.mdown;.mdwn;.mkd;.mkdn;.rmd")

    var imageExtensions: Array'String
    let imageFormats = Image.decodableFormats()
    for format in imageFormats
    {
        for extension in Tokenize.split(format.extensions, ';'u8) do
            imageExtensions.add(String.from(extension))
    }

    imageExtensions.add(String.from(".svg"))
    addViewer(&result, "image", "Image", .Image, &createImageViewer, imageExtensions.toSlice())

    var videoExtensions: Array'String
    let videoFormats = Reader.decodableFormats()
    for format in videoFormats
    {
        for extension in Tokenize.split(format.extensions, ';'u8) do
            videoExtensions.add(String.from(extension))
    }

    addViewer(&result, "video", "Video", .Video, &createVideoViewer, videoExtensions.toSlice())
    addViewer(&result, "pdf", "PDF", .Pdf, &createPdfViewer, ".pdf")
    let soundExtensions = SoundFile.decodableExtensions()
    addViewer(&result, "sound", "Sound", .Sound, &createSoundViewer, soundExtensions.toSlice())
    addViewer(&result, "font", "Font", .Font, &createFontViewer, ".ttf;.ttc")
    addViewer(&result, "midi", "MIDI", .Midi, &createMidiViewer, ".mid;.midi")
    addViewer(&result, "binary", "Binary", .Binary, &createBinaryViewer, ".exe;.dll;.sys;.ocx;.cpl;.scr;.efi;.drv;.mui;.mun;.winmd;.node;.pyd;.obj;.o;.lib;.a;.so;.elf;.ko;.axf;.dylib;.bundle;.wasm;.scc;.zip;.jar;.war;.apk;.aar;.epub;.whl;.nupkg;.vsix;.crx;.xpi;.docx;.xlsx;.pptx;.odt;.ods;.odp;.otf;.woff;.woff2;.ico;.cur;.gz;.tgz;.bz2;.tbz2;.xz;.txz;.zst;.tzst;.7z;.rar;.cab;.msi;.doc;.xls;.ppt;.ps;.eps;.class;.dex;.sqlite;.db;.pdb;.mid;.midi;.wav;.avi;.webp;.mp3;.flac;.ogg;.oga;.ogv;.mp4;.m4a;.m4v;.mov;.3gp;.3g2;.mkv;.webm;*")
    addViewer(&result, "hex", "Hexadecimal", .Hex, &createHexViewer, "*")
    addViewer(&result, "table", "Table", .Table, &createTableViewer, ".csv;.tsv;.tab")
    return result
}

impl ViewerIndex
{
    private mtd const matches(spec: const *ViewerSpec, baseName, extension: string, wildcard: bool)->bool
    {
        for supported in spec.extensions
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

    // Returns every viewer available for `fileName` in selection order.
    mtd const choices(fileName: string)->Array'ViewerChoice
    {
        var result:  retval
        var matched: Array'bool
        matched.resize(.specs.count)
        var hasExplicitMatch: bool
        var extension = String.from(Path.extension(fileName) orelse "")
        extension = extension.toLower()
        var baseName = String.from(Path.fileName(fileName) orelse "")
        baseName = baseName.toLower()

        for spec, index in .specs where .matches(spec, baseName.toString(), extension.toString(), wildcard: false)
        {
            result.add(ViewerChoice{.Viewer, index, spec.key, spec.displayName, spec.icon})
            matched[index]   = true
            hasExplicitMatch = true
        }

        // A shebang is the extension of a script the filesystem deliberately left unnamed.
        let shebang = !hasExplicitMatch ? codeShebang(fileName) : CodeShebang{}
        if shebang.found
        {
            for spec, index in .specs where spec.key == "code" and !matched[index]
            {
                result.add(ViewerChoice{.Viewer, index, spec.key, spec.displayName, spec.icon})
                matched[index] = true
                break
            }
        }

        // The key is converted explicitly: an untyped string constant used directly as an
        // aggregate-literal field of type String arrives empty (F-173).
        if BasicTextView.supports(fileName) do
            result.add(ViewerChoice{.BasicText, Swag.U64.Max, String.from(BasicTextViewerKey), appStrings().ui_BasicText, .Text})

        for spec, index in .specs where !matched[index] and .matches(spec, baseName.toString(), extension.toString(), wildcard: true) do
            result.add(ViewerChoice{.Viewer, index, spec.key, spec.displayName, spec.icon})
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
        for spec in .specs
        {
            let matchA = .matches(spec, baseA.toString(), extensionA.toString(), wildcard: false)
            let matchB = .matches(spec, baseB.toString(), extensionB.toString(), wildcard: false)
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
        for spec in .specs
        {
            for supported in spec.extensions
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

impl ViewerSpec
{
    // Creates one selected viewer and verifies the common result contract.
    mtd createView(request: const *ViewerRequest, result: *ViewerResult) fail
    {
        .create(request, result)
        if result.view and !result.failureReason.isEmpty() do
            fail InvalidFormatError{"viewer returned both a view and a failure reason"}
        if !result.view and result.failureReason.isEmpty() do
            fail InvalidFormatError{"viewer returned neither a view nor a failure reason"}
        if !result.view and result.commands do
            fail InvalidFormatError{"viewer returned commands without a view"}
    }
}
