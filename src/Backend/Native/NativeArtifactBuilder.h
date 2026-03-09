#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    Result build() const;

private:
    Result   validateNativeData() const;
    bool     isNativeStaticType(TypeRef typeRef) const;
    Result   validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
    bool     validateConstantRelocation(const MicroRelocation& relocation) const;
    Result   prepareDataSections() const;
    Result   buildStartup() const;
    Result   partitionObjects() const;
    Utf8     configuredArtifactBaseName() const;
    Utf8     artifactBaseName() const;
    Utf8     artifactExtension() const;
    fs::path configuredArtifactOutputDirectory() const;
    Result   createArtifactOutputDirectory(const fs::path& outputDir) const;
    Utf8     configuredWorkDirectoryName() const;
    Utf8     automaticWorkDirectoryName(const Utf8& baseName) const;
    Result   createWorkDirectory(const Utf8& baseName) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
