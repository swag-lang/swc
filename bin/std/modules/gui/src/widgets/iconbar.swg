#global public
using Core, Pixel

#[Swag.EnumFlags]
enum IconBarFlags
{
    Zero     = 0
    Vertical
}

struct IconBar
{
    using wnd:           Wnd

    iconBarFlags         = IconBarFlags.Zero
    iconSize:            f32
    iconPadding:         f32 = 4

    sigUpdateState:      SigArray'func||(#nonull *CommandStateEvent)
    sigCheckChanged:     SigArray'func||(#nonull *IconButton)
    sigPressed:          SigArray'func||(#nonull *IconButton)
}

impl IWnd for IconBar
{
    mtd impl onComputeStateEvent(evt: #nonull *CommandStateEvent)
    {
        evt.accepted = false
        .sigUpdateState.call(evt)
    }
}

impl IconBar
{
    mtd computeLayout()
    {
        for c in .childs
        {
            if .iconBarFlags.has(.Vertical) do
                c.dockStyle = .Top
            else do
                c.dockStyle = .Left
        }

        let pad  = 2 * .iconPadding
        let size = cast(f32) (.childs.count * (.iconSize + pad))
        if .iconBarFlags.has(.Vertical) do
            .resize(.iconSize + pad, size)
        else do
            .resize(size, .iconSize + pad)
    }

    #[Swag.Discardable]
    func create(parent: #nonull *Wnd, iconSize: f32, position: Math.Rectangle = {}, id: #null WndId = null)->#nonull *IconBar
    {
        Debug.assert(parent != null)
        var pos = position
        pos.height = iconSize
        let res = Wnd.create'IconBar(parent, null, pos, id)
        res.iconSize = iconSize
        return res
    }

    // Add a new button
    #[Swag.Discardable]
    mtd addItem(icon: Icon, btnId: #null WndId = null, iconBtnFlags = IconButtonFlags.Zero)->#nonull *IconButton
    {
        var iconT = icon
        iconT.sizeX, iconT.sizeY = .iconSize

        let size = .iconSize + 2 * .iconPadding
        let b    = IconButton.create(me, iconT, {0, 0, size, size})
        b.iconBtnFlags.set(iconBtnFlags)
        b.id        = btnId
        b.dockStyle = .Left
        b.setForm(.RoundSquare)
        .computeLayout()

        if iconBtnFlags.has(.Checkable | .CheckableToggle)
        {
            b.sigCheckChanged += func|bar = me|(btn)
            {
                bar.sigCheckChanged.call(btn)
            }
        }
        else
        {
            b.sigPressed += func|bar = me|(btn)
            {
                bar.sigPressed.call(cast(#nonull *IconButton) btn)
            }
        }

        .updateCommandState()
        return b
    }

    // Add a new checkable button
    #[Swag.Discardable]
    mtd addCheckableItem(icon: Icon, btnId: #null WndId = null)->#nonull *IconButton
    {
        return .addItem(icon, btnId, .Checkable)
    }

    // Add a new checkable button
    #[Swag.Discardable]
    mtd addCheckableToggleItem(icon: Icon, btnId: #null WndId = null)->#nonull *IconButton
    {
        return .addItem(icon, btnId, .CheckableToggle)
    }

    // Change bar flags
    mtd setIconBarFlags(add, remove = IconBarFlags.Zero)
    {
        .iconBarFlags.add(add)
        .iconBarFlags.remove(remove)
        .computeLayout()
    }

    // Returns the button with the given id
    mtd getButton(btnId: #nonull string)->#null *IconButton
    {
        let btn = .getChildById(btnId)
        if !btn do
            return null
        return cast(#null *IconButton) btn
    }
}
