#global public

using Core, Gui

// Visible strings of sCrypt.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/scrypt.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    ui_WindowTitle:      string = "sCrypt — Private virtual drives"
    ui_Subtitle:         string = "Encrypted storage that looks and behaves like a regular Windows drive."
    ui_CreateCardTitle:  string = "Create a new vault"
    ui_CreateCardHelp:   string = "Choose a fixed capacity. The complete container is randomized before it is ready."
    ui_MountCardTitle:   string = "Open an existing vault"
    ui_MountCardHelp:    string = "Unlock a container and expose it on any available drive letter. Growing the vault and changing its password ask for that same password."
    ui_MountedCardTitle: string = "Mounted drives"

    // One word per tab. The card under it says the whole sentence, so a tab that repeats it
    // spends the width of a heading to name what the heading already names.
    ui_CreateTab:  string = "Create"
    ui_OpenTab:    string = "Open"
    ui_MountedTab: string = "Mounted"

    ui_MountedCardHelp:     string = "Every drive sCrypt currently exposes. Check one to have it mounted again the next time sCrypt starts."
    ui_NoDriveMounted:      string = "No drive is mounted."
    ui_ContainerFile:       string = "CONTAINER FILE"
    ui_Browse:              string = "Browse"
    ui_FixedCapacity:       string = "FIXED CAPACITY"
    ui_NewCapacity:         string = "NEW CAPACITY"
    ui_Password:            string = "PASSWORD"
    ui_CurrentPassword:     string = "CURRENT PASSWORD"
    ui_CurrentPasswordHelp: string = "The vault only changes for whoever can already open it."
    ui_NewPassword:         string = "NEW PASSWORD"
    ui_ConfirmPassword:     string = "CONFIRM PASSWORD"
    ui_OptionalPassword:    string = "Optional — leave empty for none"
    ui_EnterAgain:          string = "Enter the password again"
    ui_ContainerPassword:   string = "Empty if the vault has none"
    ui_ExistingContainer:   string = "Encrypted container"
    ui_DriveLetter:         string = "DRIVE LETTER"
    ui_DriveHelp:           string = "The drive is available to Windows while sCrypt runs, and appears under Mounted."
    ui_ReadOnly:            string = "Mount read only"
    ui_ReadOnlyHelp:        string = "The drive opens for reading alone: nothing can add to the vault, change it, or delete from it while it is mounted."
    ui_RemovePasswordHelp:  string = "Leave it empty to remove the password. The vault then opens without one."
    ui_CurrentCapacityHelp: string = "Currently %. A vault can only grow."
    ui_CreateVault:         string = "Create encrypted vault"
    ui_StopCreating:        string = "Stop creating"
    ui_StopGrowing:         string = "Stop growing"
    ui_ChangePassword:      string = "Password…"
    ui_Resize:              string = "Capacity…"
    ui_MountDrive:          string = "Mount drive"
    ui_Unmount:             string = "Unmount"
    ui_ColStartup:          string = "AT STARTUP"
    ui_ColDrive:            string = "DRIVE"
    ui_ColSize:             string = "SIZE"
    ui_ColAvailable:        string = "AVAILABLE"
    ui_ColVault:            string = "VAULT"
    ui_Desktop:             string = "Desktop"
    ui_LanguageSystem:      string = "System language"
    dlg_TitleCreate:        string = "Create an sCrypt container"
    dlg_TitleOpen:          string = "Open an encrypted container"
    dlg_TitlePassword:      string = "Change the vault password"
    dlg_TitleResize:        string = "Grow the vault"
    dlg_TitleUnlock:        string = "Unlock %"     // '%' is the file name of the container being mounted at startup.
    dlg_BtnCreate:          string = "Create"
    dlg_BtnOpen:            string = "Open"
    dlg_BtnApply:           string = "Apply"
    dlg_BtnGrow:            string = "Grow"
    dlg_BtnSkip:            string = "Skip"
    msg_Ready:              string = "Ready — create a vault or choose one to open."
    msg_OperationStopped:   string = "The operation stopped."
    msg_SystemError:        string = "System error."
    msg_SizeInvalid:        string = "The container size is invalid."
    msg_SizeTooLarge:       string = "The container size is too large."
    msg_SizeMinimum:        string = "The minimum container size is % MiB."
    msg_ChooseCreateFile:   string = "Choose the container file to create."
    msg_FileExists:         string = "This file already exists. Choose a new name to avoid data loss."
    msg_PasswordRequired:   string = "A password is required."
    msg_PasswordMismatch:   string = "The passwords do not match."
    msg_CreateFailed:       string = "Could not create the container."
    msg_Randomizing:        string = "Creating and randomizing the container... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_StopRequested:      string = "Stopping..."
    msg_CreateCanceled:     string = "Container creation canceled. Nothing was left on disk."
    msg_ChooseExisting:     string = "Choose an existing container."
    msg_AlreadyMounted:     string = "A drive is already exposing this container."
    msg_UnmountFirst:       string = "This vault is mounted. Unmount it before changing it."
    msg_NoDriveLetter:      string = "No drive letter is available."
    msg_StartingDriver:     string = "Starting the portable filesystem driver..."
    msg_Unmounting:         string = "Synchronizing and unmounting the encrypted drive..."
    msg_CreateStopped:      string = "Container creation stopped."
    msg_Created:            string = "Container created. It is ready to open."
    msg_MountFailed:        string = "Could not mount the virtual disk."
    msg_MountStopped:       string = "Mount stopped."
    msg_Mounted:            string = "Encrypted drive mounted on %."
    msg_MountedReadOnly:    string = "Encrypted drive mounted read only on %."
    msg_UnmountSyncStopped: string = "The drive was unmounted, but final synchronization stopped."
    msg_Unmounted:          string = "Drive unmounted safely."
    msg_OnlyGrows:          string = "A vault can only grow. Choose a capacity above the current one."
    msg_Growing:            string = "Randomizing the added space... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_GrowCanceled:       string = "Growing stopped. The vault kept its previous size."
    msg_GrowStopped:        string = "Growing stopped."
    msg_GrowFailed:         string = "Could not grow the container."
    msg_Grown:              string = "The vault now holds %."
    msg_ChangingPassword:   string = "Rewriting the key slot..."
    msg_PasswordChanged:    string = "The vault now opens with the new password."
    msg_PasswordRemoved:    string = "The password was removed. The vault now opens without one."
    msg_PasswordFailed:     string = "Could not change the password."
    msg_PasswordStopped:    string = "The password change stopped."

    // What a failure of each [[ErrorKind]] says. The volume layer reports the kind and an
    // English diagnostic for a report; these are the sentences a reader sees instead.
    msg_ErrPasswordOrDamaged: string = "The password is incorrect or the container is damaged."     // The container did not open, and the format refuses to say which of the two it was.
    msg_ErrDamaged:           string = "The container is damaged."                                  // An open container no longer reads back what it stored.
    msg_ErrNotFound:          string = "The container could not be found."                          // The named container or entry does not exist.
    msg_ErrAlreadyExists:     string = "A file with this name already exists."                      // The name is taken.
    msg_ErrAccessDenied:      string = "Access to the container was refused."                       // The entry exists and refuses the operation.
    msg_ErrReadOnly:          string = "The vault is mounted read only."                            // The container refuses every change.
    msg_ErrDiskFull:          string = "There is no room left in the container."                    // No room is left for blocks, metadata, or key slots.
    msg_ErrIo:                string = "The container could not be read or written."                // The underlying file could not be reached.
    msg_ErrInvalidRequest:    string = "The container cannot answer that request."                  // The operation asked for something the container refuses outright.
}

private const FrenchStringsName = "lang/fr/scrypt.tweak"
private const FrenchStrings = #include("../datas/lang/fr/scrypt.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sCrypt in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the sCrypt string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "scrypt")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
