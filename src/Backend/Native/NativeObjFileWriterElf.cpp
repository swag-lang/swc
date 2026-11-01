#include "pch.h"
#include "Backend/Native/NativeObjFileWriterElf.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeImageBuilder.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result NativeObjFileWriterElf::buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description)
{
    outBytes.clear();
    if (builder_->compiler().buildCfg().backend.debugInfo)
        return builder_->reportError(DiagnosticId::cmd_err_link_elf_object, Diagnostic::ARG_BECAUSE, "Linux native source debug information is not implemented");
    LinkImage image;
    SWC_RESULT(NativeImageBuilder::buildObject(image, *builder_, description));
    for (const NativeFunctionInfo* function : description.functions)
    {
        if (function->exported && !function->exportName.empty())
            image.exports.push_back({.name = function->exportName, .symbolName = function->symbolName});
    }
    Diagnostic diagnostic;
    if (!buildElfObject(outBytes, diagnostic, image))
        return builder_->reportError(diagnostic);
    return Result::Continue;
}

SWC_END_NAMESPACE();
