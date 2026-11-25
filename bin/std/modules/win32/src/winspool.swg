#global export
#global if #os == Swag.TargetOs.Windows

#foreignlib("winspool")

const PRINTER_ENUM_LOCAL       = 0x00000002'u32
const PRINTER_ENUM_CONNECTIONS = 0x00000004'u32

const PRINTER_ATTRIBUTE_FAX = 0x00004000'u32

const DM_ORIENTATION = 0x00000001'u32
const DM_PAPERSIZE   = 0x00000002'u32
const DM_PAPERLENGTH = 0x00000004'u32
const DM_PAPERWIDTH  = 0x00000008'u32
const DM_COPIES      = 0x00000100'u32

const DM_OUT_BUFFER = 2'u32
const DM_IN_BUFFER  = 8'u32

const DMORIENT_PORTRAIT  = 1's16
const DMORIENT_LANDSCAPE = 2's16
const DMPAPER_LETTER     = 1's16
const DMPAPER_LEGAL      = 5's16
const DMPAPER_A4         = 9's16

struct DEVMODEW
{
    public
    {
        dmDeviceName:    [32] WCHAR
        dmSpecVersion:   WORD
        dmDriverVersion: WORD
        dmSize:          WORD
        dmDriverExtra:   WORD
        dmFields:        DWORD

        using DUMMYUNIONNAME: union
        {
            using DUMMYSTRUCTNAME: struct
            {
                dmOrientation:   SHORT
                dmPaperSize:     SHORT
                dmPaperLength:   SHORT
                dmPaperWidth:    SHORT
                dmScale:         SHORT
                dmCopies:        SHORT
                dmDefaultSource: SHORT
                dmPrintQuality:  SHORT
            }

            using DUMMYSTRUCTNAME2: struct
            {
                dmPosition: POINTL
                dmDisplayOrientation: DWORD
                dmDisplayFixedOutput: DWORD
            }
        }

        dmColor:       SHORT
        dmDuplex:      SHORT
        dmYResolution: SHORT
        dmTTOption:    SHORT
        dmCollate:     SHORT
        dmFormName:    [32] WCHAR
        dmLogPixels:   WORD
        dmBitsPerPel:  DWORD
        dmPelsWidth:   DWORD
        dmPelsHeight:  DWORD

        using DUMMYUNIONNAME2: union
        {
            dmDisplayFlags: DWORD
            dmNup: DWORD
        }

        dmDisplayFrequency: DWORD
        dmICMMethod:        DWORD
        dmICMIntent:        DWORD
        dmMediaType:        DWORD
        dmDitherType:       DWORD
        dmReserved1:        DWORD
        dmReserved2:        DWORD
        dmPanningWidth:     DWORD
        dmPanningHeight:    DWORD
    }
}

struct PRINTER_INFO_4W
{
    public
    {
        pPrinterName: LPWSTR
        pServerName:  LPWSTR
        Attributes:   DWORD
    }
}

struct PRINTER_INFO_5W
{
    public
    {
        pPrinterName:             LPWSTR
        pPortName:                LPWSTR
        Attributes:               DWORD
        DeviceNotSelectedTimeout: DWORD
        TransmissionRetryTimeout: DWORD
    }
}

struct PRINTER_DEFAULTSW
{
    public
    {
        pDatatype:     LPWSTR
        pDevMode:      *DEVMODEW?
        DesiredAccess: DWORD
    }
}

#[Swag.Foreign("winspool.drv", callconv: Swag.CallConv.C), Swag.Discardable]
{
    func EnumPrintersW(flags: DWORD, name: LPWSTR, level: DWORD, printers: [*] BYTE?, size: DWORD, needed, returned: *DWORD)->BOOL
    func GetDefaultPrinterW(name: LPWSTR, length: *DWORD)->BOOL
    func OpenPrinterW(name: LPWSTR, printer: *HANDLE, defaults: *PRINTER_DEFAULTSW?)->BOOL
    func GetPrinterW(printer: HANDLE, level: DWORD, info: [*] BYTE?, size: DWORD, needed: *DWORD)->BOOL
    func ClosePrinter(printer: HANDLE)->BOOL
    func DocumentPropertiesW(wnd: HWND, printer: HANDLE, name: LPWSTR, output, input: *DEVMODEW?, mode: DWORD)->LONG
}

#assert(#sizeof(DEVMODEW) == 220)
