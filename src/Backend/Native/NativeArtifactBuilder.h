#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

struct NativeArtifactPaths
{
    Utf8     baseName;
    Utf8     workDirRootName;
    Utf8     artifactExtension;
    fs::path workDirRoot;
    fs::path artifactOutputDir;
    fs::path artifactPath;
};

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    Result build() const;
    void   queryPaths(NativeArtifactPaths& outPaths) const;

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
    fs::path configuredArtifactOutputDirectory(const fs::path& defaultOutputDir) const;
    Result   createArtifactOutputDirectory(const fs::path& outputDir) const;
    Utf8     configuredWorkDirectoryName() const;
    Utf8     automaticWorkDirectoryName(const Utf8& baseName) const;
    fs::path workDirectoryRoot(const Utf8& baseName) const;
    fs::path workDirectory(const Utf8& baseName, uint32_t workDirIndex) const;
    Result   createWorkDirectory(const Utf8& baseName) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
