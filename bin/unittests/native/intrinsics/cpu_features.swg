const HostCryptoFeatures = #run
{
    return [Swag.hasCpuFeature(.Aes), Swag.hasCpuFeature(.CarrylessMultiply), Swag.hasCpuFeature(.Sha)]
}

#test
{
    Swag.require(HostCryptoFeatures[0] == Swag.hasCpuFeature(.Aes))
    Swag.require(HostCryptoFeatures[1] == Swag.hasCpuFeature(.CarrylessMultiply))
    Swag.require(HostCryptoFeatures[2] == Swag.hasCpuFeature(.Sha))
}
