#pragma once
#include "Backend/Linker/LinkImage.h"
#include "Backend/Runtime.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

// A fully self-contained description of one link.
//
// prepareLink() fills the inputs from compiler state on the foreground thread; executeLink() turns
// them into the final artifact, touching no compiler/logger/diagnostic state so it can run on a
// background thread overlapped with other module work; finishLink() reports the result and validates
// the artifact back on the foreground thread.
struct LinkJob
{
    enum class Output : uint8_t
    {
        Executable,
        SharedLibrary,
        StaticLibrary,
    };

    // Inputs (filled by prepareLink).
    Output                output   = Output::Executable;
    Runtime::TargetOs     targetOs = Runtime::TargetOs::Windows; // selects the artifact writer
    fs::path              outputPath;
    fs::path              buildDir;
    LinkImage             image;          // Executable / SharedLibrary
    std::vector<LinkArchiveMember> archiveMembers; // StaticLibrary: prepared object members

    // Outputs (filled by executeLink). On failure, error carries a ready-to-report diagnostic built
    // off the foreground thread (Diagnostic::get/addArgument touch no compiler/logger state); finishLink
    // reports it back on the foreground thread.
    bool       executed = false;
    bool       ok       = false;
    Diagnostic error;
};

SWC_END_NAMESPACE();
