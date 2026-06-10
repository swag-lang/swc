#pragma once
#include "Backend/Linker/LinkImage.h"
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

// Serialises the resolved link inputs into the final on-disk artifact bytes for one target format:
// executable/shared-library images plus the static and import libraries that accompany them. A
// concrete subclass exists per object/container format (PE today, ELF/Mach-O later); create() selects
// it from the target OS, mirroring NativeObjFileWriter. Every method is self-contained so it can run
// on a background link thread, touching nothing but its arguments.
class ImageWriter
{
public:
    virtual ~ImageWriter() = default;

    static std::unique_ptr<ImageWriter> create(Runtime::TargetOs targetOs);

    // Executable or shared-library image. Returns false and fills outDiag on an unresolved symbol or a
    // structural problem.
    virtual bool writeImage(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const LinkImage& image) = 0;

    // Static library archive built from prepared object members. Returns false and fills outDiag on a
    // malformed member.
    virtual bool buildStaticArchive(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& members) = 0;

    // Import library that accompanies a shared library so dependents can resolve its exports by name.
    virtual void buildImportLibrary(std::vector<std::byte>& outBytes, std::string_view dllFileName, const std::vector<Utf8>& exportNames) = 0;
};

SWC_END_NAMESPACE();
