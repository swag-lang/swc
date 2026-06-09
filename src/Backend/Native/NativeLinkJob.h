#pragma once
#include "Backend/Native/NativeLinkImage.h"

SWC_BEGIN_NAMESPACE();

// A fully self-contained description of one link.
//
// prepareLink() fills the inputs from compiler state on the foreground thread; executeLink() turns
// them into the final artifact, touching no compiler/logger/diagnostic state so it can run on a
// background thread overlapped with other module work; finishLink() reports the result and validates
// the artifact back on the foreground thread.
struct NativeLinkJob
{
    enum class Output : uint8_t
    {
        Executable,
        SharedLibrary,
        StaticLibrary,
    };

    // Inputs (filled by prepareLink).
    Output                output = Output::Executable;
    fs::path              outputPath;
    fs::path              buildDir;
    LinkImage             image;          // Executable / SharedLibrary
    std::vector<fs::path> archiveMembers; // StaticLibrary: object files to archive

    // Outputs (filled by executeLink).
    bool executed = false;
    bool ok       = false;
    Utf8 errorText;
};

SWC_END_NAMESPACE();
