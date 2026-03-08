#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    bool build() const;

private:
    bool        validateNativeData() const;
    bool        isNativeStaticType(TypeRef typeRef) const;
    bool        validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
    bool        validateConstantRelocation(const MicroRelocation& relocation) const;
    bool        prepareDataSections() const;
    bool        buildStartup() const;
    bool        partitionObjects() const;
    Utf8        artifactBaseName() const;
    Utf8        artifactExtension() const;
    bool        createWorkDirectory(const Utf8& baseName) const;
    static Utf8 sanitizeName(Utf8 value);

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
