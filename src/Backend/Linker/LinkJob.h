#pragma once
#include "Backend/Linker/LinkDebugInfo.h"
#include "Backend/Linker/LinkImage.h"
#include "Backend/Runtime.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

// A fully self-contained description of one link.
//
// prepareLink() fills the inputs from compiler state on the foreground thread; executeLink() turns
// them into the final artifact, touching no compiler/logger/diagnostic state so it can run on a
// background thread overlapped with other module work; finishLink() reports the result and validates
// the artifact back on the foreground thread.
//
// Two modes share this one pipeline: Internal links the LinkImage in process (the integrated PE
// linker, PELinker), while External shells out to the platform toolchain (link.exe / lib.exe, the
// CoffLinker, selected by --external-link). Keeping both behind one job keeps the async workspace
// pipeline and the call sites identical for either backend.
struct LinkJob
{
    enum class Mode : uint8_t
    {
        Internal,
        External,
    };

    enum class Output : uint8_t
    {
        Executable,
        SharedLibrary,
        StaticLibrary,
    };

    // Common inputs (filled by prepareLink).
    Mode              mode     = Mode::Internal;
    Output            output   = Output::Executable;
    Runtime::TargetOs targetOs = Runtime::TargetOs::Windows; // selects the artifact writer
    fs::path          outputPath;
    fs::path          pdbPath; // debug-info sidecar; empty when debug info is disabled
    fs::path          buildDir;

    // Internal-mode inputs.
    LinkImage                      image;          // Executable / SharedLibrary
    std::vector<LinkArchiveMember> archiveMembers; // StaticLibrary: prepared object members
    LinkDebugInfo                  debugInfo;      // self-contained debug records lowered by prepareLink

    // External-mode inputs (filled by CoffLinker::prepareLink).
    fs::path                              exePath;
    std::vector<Utf8>                     runArgs;
    std::function<bool(std::string_view)> outputLineFilter;

    // External-mode results (filled by executeLink when shelling out).
    std::string          capturedOutput;
    Utf8                 systemError;
    uint32_t             exitCode  = 0;
    Os::ProcessRunResult runResult = Os::ProcessRunResult::Ok;

    // Common outputs (filled by executeLink). On internal-mode failure, error carries a ready-to-report
    // diagnostic built off the foreground thread (Diagnostic::get/addArgument touch no compiler/logger
    // state); finishLink reports it back on the foreground thread.
    bool       executed = false;
    bool       ok       = false;
    Diagnostic error;
};

SWC_END_NAMESPACE();
