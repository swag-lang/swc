// Every command id minted by newCmdId embeds the owning scope name
// ("ActionSelection.SelectAll"), so an action accepts a command exactly when the
// id starts with its own scope. This mixin generates the accept() implementation
// from that rule; invoke it inside the 'impl IActionUI for X' block.
#[Swag.Mixin]
func acceptOwnCmdIds()
{
    #ast "mtd impl accept(cxt: ActionContext)->bool { return Utf8.startsWith(cxt.id, \"" ++ #scopename ++ ".\") }"
}
