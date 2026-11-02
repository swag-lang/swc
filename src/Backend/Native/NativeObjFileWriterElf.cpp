#include "pch.h"
#include "Backend/Native/NativeObjFileWriterElf.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeImageBuilder.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result NativeObjFileWriterElf::buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description)
{
    outBytes.clear();
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
