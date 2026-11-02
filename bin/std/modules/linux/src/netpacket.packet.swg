#global if #os == Swag.TargetOs.Linux
#global export

struct sockaddr_ll
{
    public
    {
        sll_family:   u16
        sll_protocol: u16
        sll_ifindex:  s32
        sll_hatype:   u16
        sll_pkttype:  u8
        sll_halen:    u8
        sll_addr:     [8] u8
    }
}

#assert(#sizeof(sockaddr_ll) == 20)
#assert(#offsetof(sockaddr_ll.sll_addr) == 12)
