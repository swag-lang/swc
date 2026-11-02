#global if #os == Swag.TargetOs.Linux
#global export

const AF_PACKET = 17'u16

struct sockaddr
{
    public
    {
        sa_family: u16
        sa_data:   [14] u8
    }
}

#assert(#sizeof(sockaddr) == 16)
