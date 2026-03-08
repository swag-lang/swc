#include "pch.h"
#include "Backend/Native/NativeObjectFileWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

std::unique_ptr<NativeObjectFileWriter> NativeObjectFileWriter::create(NativeBackendBuilder& builder)
{
    const auto format = getNativeObjectFormat(builder.ctx().cmdLine().targetOs);
    if (!format)
        return {};

    switch (*format)
    {
        case NativeObjectFormat::WindowsCoff:
            return createNativeObjectFileWriterWindowsCoff(builder);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
