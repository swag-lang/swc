#global public

using Core, Pixel

// Selects the axis along which an icon bar arranges its buttons.
enum IconBarOrientation
{
    Horizontal     // Arranges buttons from left to right.
    Vertical       // Arranges buttons from top to bottom.
}

// Arranges icon buttons and forwards their action and checked-state signals.
struct IconBar
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            orientation      = IconBarOrientation.Horizontal     // Current button layout axis.
            iconSize:    f32                                     // Square icon size in logical units.
            itemPadding: f32 = 4                                 // Padding around every icon in logical units.
        }

        sigComputeState:   SigArray'func||(*CommandStateEvent)     // Invoked when child command state must be computed.
        sigCheckedChanged: SigArray'func||(*IconButton)            // Emitted after a child changes checked state.
        sigPressed:        SigArray'func||(*IconButton)            // Emitted after a plain child button is activated.
    }
}

impl IWnd for IconBar
{
    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        evt.accepted = false
        .sigComputeState.call(evt)
    }
}

private impl IconBar
{
    mtd computeLayout()
    {
        for child in .children
        {
            if .orientation == .Vertical do
                child.dockStyle = .Top
            else do
                child.dockStyle = .Left
        }

        let paddedIconSize = .iconSize + 2 * .itemPadding
        let barLength      = cast(f32) .children.count * paddedIconSize
        if .orientation == .Vertical do
            .resize(paddedIconSize, barLength)
        else do
            .resize(barLength, paddedIconSize)
    }

    mtd updateButtonMetrics()
    {
        let size = .iconSize + 2 * .itemPadding
        for child in .children
        {
            let button = cast(*IconButton) child
            button.setIconSize(.iconSize, .iconSize)
            button.resize(size, size)
        }
    }
}

impl IconBar
{
    // Creates an empty icon bar with a non-negative icon size and item padding.
    #[Swag.Discardable]
    func create(parent: *Wnd, iconSize: f32, position: Math.Rectangle = {}, id: WndId? = null, orientation = IconBarOrientation.Horizontal, itemPadding = 4'f32)->*IconBar
    {
        Debug.assert(parent != null)
        Debug.assert(iconSize >= 0 and itemPadding >= 0)
        let result = Wnd.create'IconBar(parent, null, position, id)
        result.iconSize    = iconSize
        result.itemPadding = itemPadding
        result.orientation = orientation
        result.computeLayout()
        return result
    }

    // Appends an icon button with optional command identifier and interaction flags.
    #[Swag.Discardable]
    mtd addButton(icon: Icon, id: WndId? = null, flags = IconButtonFlags.None)->*IconButton
    {
        var sizedIcon = icon
        sizedIcon.sizeX, sizedIcon.sizeY = .iconSize

        let size   = .iconSize + 2 * .itemPadding
        let button = IconButton.create(me, sizedIcon, {0, 0, size, size}, id, flags)
        button.dockStyle = .orientation == .Vertical ? .Top : .Left
        button.setForm(.orientation == .Horizontal ? .RoundedRectangle : .Rectangle)
        button.setCheckIndicator(.orientation == .Horizontal ? .Frame : .Left)

        if flags.has(.Radio) or flags.has(.Toggle) do
            button.sigCheckedChanged += func|bar = me|(btn) { bar.sigCheckedChanged.call(btn) }
        else do
            button.sigPressed += func|bar = me|(btn) { bar.sigPressed.call(cast(*IconButton) btn) }

        .computeLayout()
        return button
    }

    // Appends a radio-style button that remains checked after its first activation.
    #[Swag.Discardable]
    mtd addRadioButton(icon: Icon, id: WndId? = null)->*IconButton
    {
        return .addButton(icon, id, .Radio)
    }

    // Appends a toggle button that flips checked state on every activation.
    #[Swag.Discardable]
    mtd addToggleButton(icon: Icon, id: WndId? = null)->*IconButton
    {
        return .addButton(icon, id, .Toggle)
    }

    // Changes the layout axis and immediately recomputes the bar size.
    mtd setOrientation(orientation: IconBarOrientation)
    {
        if .orientation == orientation do
            return
        .orientation = orientation
        for child in .children
        {
            let button = cast(*IconButton) child
            button.setForm(.orientation == .Horizontal ? .RoundedRectangle : .Rectangle)
            button.setCheckIndicator(.orientation == .Horizontal ? .Frame : .Left)
        }

        .computeLayout()
    }

    // Changes padding around every icon and immediately recomputes the bar size.
    mtd setItemPadding(padding: f32)
    {
        Debug.assert(padding >= 0)
        if .itemPadding == padding do
            return
        .itemPadding = padding
        .updateButtonMetrics()
        .computeLayout()
    }

    // Changes the square icon size and immediately updates every child button.
    mtd setIconSize(size: f32)
    {
        Debug.assert(size >= 0)
        if .iconSize == size do
            return
        .iconSize = size
        .updateButtonMetrics()
        .computeLayout()
    }

    // Returns the child icon button carrying one command identifier, or null when absent.
    mtd buttonById(id: WndId)->*IconButton?
    {
        let button = .childById(id)
        if !button do
            return null
        return cast(*IconButton?) button
    }
}
