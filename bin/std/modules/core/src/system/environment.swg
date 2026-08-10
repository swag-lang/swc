#global public
#global namespace Env

// Returns the process command-line arguments.
//
// The returned slice is borrowed from the runtime and remains valid for the
// lifetime of the process. Element zero is the executable path when supplied by
// the operating system.
func arguments()->const [..] string => @args

// Returns the command-line argument at `index`, or `null` when it is out of range.
func argument(index: u32)->#null string
{
    let args = @args
    if index >= @countof(args) do
        return null
    return args[index]
}

// Returns whether the command line contains `argument` exactly.
func hasArgument(argument: string)->bool
{
    return Slice.contains(@args, argument)
}

// Returns the executable path reported as command-line argument zero.
//
// Returns an empty string when the runtime did not provide any arguments.
func executablePath()->string
{
    let args = @args
    if @countof(args) == 0 do
        return ""
    return args[0]
}

// Identifies a well-known operating-system directory.
enum SpecialDirectory
{
    Temp               // Temporary files for the current user.
    Font               // Installed system fonts.
    UserAppData        // Roaming application data for the current user.
    UserDocuments      // Documents for the current user.
    CommonAppData      // Application data shared by all users.
    Desktop            // Desktop for the current user.
    UserPictures       // Pictures for the current user.
    UserVideos         // Videos for the current user.
    UserMusic          // Music for the current user.
    CommonPictures     // Pictures shared by all users.
    CommonVideos       // Videos shared by all users.
    CommonMusic        // Music shared by all users.
}

// Describes a physical monitor.
#[Swag.Operators(opEquals, opCompare)]
struct Monitor
{
    public
    {
        bounds:           Math.Rectangle     // Logical bounds in desktop coordinates.
        workArea:         Math.Rectangle     // Logical bounds available to applications.
        scaleFactor:      f32                // Ratio from logical coordinates to physical pixels.
        physicalBounds:   Math.Rectangle     // Physical-pixel bounds in desktop coordinates.
        physicalWorkArea: Math.Rectangle     // Physical-pixel bounds available to applications.
    }
}

// Returns the monitor containing `point`, or the nearest monitor otherwise.
//
// `point` is in physical desktop pixels, the space of window positions and of the
// cursor once the process is DPI aware.
func monitorForPoint(point: Math.Point)->Env.Monitor
{
    let monitors = Env.getMonitors()

    // First pass: exact containment
    for m in monitors
    {
        let r = m.physicalBounds
        if point.x >= r.x and point.x <= r.right() and point.y >= r.y and point.y <= r.bottom() do
            return m
    }

    // Second pass: nearest (min distance from point to monitor rect)
    var bestM: retval
    var bestD2 = Swag.F32.Inf
    for m in monitors
    {
        let r  = m.physicalBounds
        let cx = Math.clamp(point.x, r.x, r.right())
        let cy = Math.clamp(point.y, r.y, r.bottom())
        let dx = point.x - cx
        let dy = point.y - cy
        let d2 = dx * dx + dy * dy
        if d2 < bestD2
        {
            bestD2 = d2
            bestM  = m
        }
    }

    return bestM
}

// Returns the monitor with the largest intersection with `rectangle`.
//
// `rectangle` is in physical desktop pixels. The first monitor is returned when
// the rectangle does not intersect a monitor.
func monitorForRectangle(rectangle: Math.Rectangle)->Env.Monitor
{
    var result: retval
    var bestSurf = 0'f32
    let monitors = Env.getMonitors()
    for m in monitors
    {
        var r1 = rectangle
        r1.intersect(m.physicalBounds)
        let surf = r1.width * r1.height
        if surf > bestSurf
        {
            bestSurf = surf
            result   = m
        }
    }

    if bestSurf == 0 do
        result = monitors[0]
    return result
}

private var g_CmdLineArgs: #null const [..] string

// Identifies a virtual-desktop system metric.
enum SystemMetric
{
    DesktopX          // Left edge of the virtual desktop.
    DesktopY          // Top edge of the virtual desktop.
    DesktopWidth      // Width of the virtual desktop.
    DesktopHeight     // Height of the virtual desktop.
}

#premain
{
    if !(@rtflags & .FromCompiler)
    {
        let str = getNativeArgs()
        if @countof(str) do
            @pinfos.args = str
    }
}
