#global if #os == Swag.TargetOs.Linux
#global private

tls var counter = 41'u64

#run
{
    counter += 1
    Swag.assert(counter == 42)
}
