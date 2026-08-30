#global public

using Core, Gui

// Visible strings of Swag Vault.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/vault.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    ui_WindowTitle:      string = "Swag Vault — Private virtual drives"
    ui_Subtitle:         string = "Encrypted storage that looks and behaves like a regular Windows drive."
    ui_CreateCardTitle:  string = "Create a new vault"
    ui_CreateCardHelp:   string = "Choose a fixed capacity. The complete container is randomized before it is ready."
    ui_MountCardTitle:   string = "Open an existing vault"
    ui_MountCardHelp:    string = "Enter the vault access once here. Mounting and every change below use the same password and key files."
    ui_MountedCardTitle: string = "Mounted drives"
    ui_OptionsCardTitle: string = "Privacy and automatic unmounting"

    // One word per tab. The card under it says the whole sentence, so a tab that repeats it
    // spends the width of a heading to name what the heading already names.
    ui_CreateTab:  string = "Create"
    ui_OpenTab:    string = "Open"
    ui_MountedTab: string = "Mounted"
    ui_OptionsTab: string = "Options"

    ui_MountedCardHelp:      string = "Every drive Swag Vault currently exposes. Check one to have it mounted again the next time Swag Vault starts."
    ui_OptionsCardHelp:      string = "Keep vault locations private and choose when protected drives close automatically."
    ui_NoDriveMounted:       string = "No drive is mounted."
    ui_ContainerFile:        string = "CONTAINER FILE"
    ui_Browse:               string = "Browse"
    ui_FixedCapacity:        string = "FIXED CAPACITY"
    ui_NewCapacity:          string = "NEW CAPACITY"
    ui_Password:             string = "PASSWORD"
    ui_NewPassword:          string = "NEW PASSWORD"
    ui_ConfirmPassword:      string = "CONFIRM PASSWORD"
    ui_OptionalPassword:     string = "Optional — leave empty for none"
    ui_EnterAgain:           string = "Enter the password again"
    ui_ContainerPassword:    string = "Empty if the vault has none"
    ui_KeyFiles:             string = "KEY FILES"
    ui_KeyFilesHelp:         string = "Every listed file is required. File contents are used; the files can be moved without changing access."
    ui_NoKeyFiles:           string = "No key files"
    ui_AddKeyFiles:          string = "Add existing key files"
    ui_GenerateKeyFile:      string = "Create a random key file"
    ui_RemoveKeyFile:        string = "Remove the selected key file"
    ui_ExistingContainer:    string = "Encrypted container"
    ui_DriveLetter:          string = "DRIVE LETTER"
    ui_DriveHelp:            string = "The drive is available to Windows while Swag Vault runs, and appears under Mounted."
    ui_ReadOnly:             string = "Mount read only"
    ui_ReadOnlyHelp:         string = "The drive opens for reading alone: nothing can add to the vault, change it, or delete from it while it is mounted."
    ui_PrivacyMode:          string = "Privacy mode"
    ui_PrivacyModeHelp:      string = "Do not save container paths, browse history, or startup mounts."
    ui_UnmountOnLock:        string = "Unmount when Windows locks"
    ui_UnmountOnLockHelp:    string = "Protected drives close as soon as the current Windows session is locked."
    ui_UnmountOnSuspend:     string = "Unmount before sleep"
    ui_UnmountOnSuspendHelp: string = "Protected drives close when Windows suspends the computer."
    ui_UnmountOnIdle:        string = "Unmount after inactivity"
    ui_UnmountOnIdleHelp:    string = "Protected drives close after Windows has received no keyboard or pointer input for the selected time."
    ui_IdleTimeout:          string = "INACTIVITY TIMEOUT"
    ui_Minutes:              string = "% minutes"
    ui_RemovePasswordHelp:   string = "Leave it empty to remove only the password. Any selected key files remain required."
    ui_NewCapacityHelp:      string = "Changing capacity may move used blocks that no longer fit."
    ui_KeepCapacity:         string = "Keep the current capacity"
    ui_KeepCapacityHelp:     string = "Refresh the randomized physical size without moving vault data."
    ui_CreateVault:          string = "Create encrypted vault"
    ui_StopCreating:         string = "Stop creating"
    ui_StopResizing:         string = "Stop resizing"
    ui_ChangePassword:       string = "Password…"
    ui_ChangeKeyFiles:       string = "Key files…"
    ui_Resize:               string = "Capacity and camouflage…"
    ui_MountDrive:           string = "Mount drive"
    ui_Unmount:              string = "Unmount"
    ui_ColStartup:           string = "AT STARTUP"
    ui_ColDrive:             string = "DRIVE"
    ui_ColSize:              string = "SIZE"
    ui_ColAvailable:         string = "AVAILABLE"
    ui_ColVault:             string = "VAULT"
    ui_Desktop:              string = "Desktop"
    dlg_TitleCreate:         string = "Create a Swag Vault container"
    dlg_TitleOpen:           string = "Open an encrypted container"
    dlg_TitlePassword:       string = "Change the vault password"
    dlg_TitleKeyFiles:       string = "Select key files"
    dlg_TitleGenerateKey:    string = "Create a random key file"
    dlg_TitleChangeKeyFiles: string = "Change the vault key files"
    dlg_TitleResize:         string = "Change capacity or camouflage"
    dlg_TitleUnlock:         string = "Unlock %"     // '%' is the file name of the container being mounted at startup.
    dlg_BtnCreate:           string = "Create"
    dlg_BtnOpen:             string = "Open"
    dlg_BtnAdd:              string = "Add"
    dlg_BtnApply:            string = "Apply"
    dlg_BtnSkip:             string = "Skip"
    msg_Ready:               string = "Ready — create a vault or choose one to open."
    msg_OperationStopped:    string = "The operation stopped."
    msg_SystemError:         string = "System error."
    msg_SizeInvalid:         string = "The container size is invalid."
    msg_SizeTooLarge:        string = "The container size is too large."
    msg_SizeMinimum:         string = "The minimum container size is % MiB."
    msg_ChooseCreateFile:    string = "Choose the container file to create."
    msg_FileExists:          string = "This file already exists. Choose a new name to avoid data loss."
    msg_PasswordRequired:    string = "A password is required."
    msg_PasswordMismatch:    string = "The passwords do not match."
    msg_KeyFileCreateFailed: string = "Could not create the random key file."
    msg_CreateFailed:        string = "Could not create the container."
    msg_Randomizing:         string = "Creating and randomizing the container... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_StopRequested:       string = "Stopping..."
    msg_CreateCanceled:      string = "Container creation canceled. Nothing was left on disk."
    msg_ChooseExisting:      string = "Choose an existing container."
    msg_AlreadyMounted:      string = "A drive is already exposing this container."
    msg_UnmountFirst:        string = "This vault is mounted. Unmount it before changing it."
    msg_NoDriveLetter:       string = "No drive letter is available."
    msg_StartingDriver:      string = "Starting the portable filesystem driver..."
    msg_Unmounting:          string = "Synchronizing and unmounting the encrypted drive..."
    msg_CreateStopped:       string = "Container creation stopped."
    msg_Created:             string = "Container created. It is ready to open."
    msg_MountFailed:         string = "Could not mount the virtual disk."
    msg_MountStopped:        string = "Mount stopped."
    msg_Mounted:             string = "Encrypted drive mounted on %."
    msg_MountedReadOnly:     string = "Encrypted drive mounted read only on %."
    msg_UnmountSyncStopped:  string = "The drive was unmounted, but final synchronization stopped."
    msg_Unmounted:           string = "Drive unmounted safely."
    msg_Resizing:            string = "Resizing the container... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_Camouflaging:        string = "Refreshing physical camouflage... %{#0}%%"
    msg_ResizeCanceled:      string = "Resizing stopped. The vault kept its previous size."
    msg_ResizeStopped:       string = "Resizing stopped."
    msg_ResizeFailed:        string = "Could not resize the container."
    msg_Resized:             string = "The vault now holds %."
    msg_Camouflaged:         string = "The vault kept its capacity and received a new physical size."
    msg_AutoUnmounted:       string = "Protected drives were unmounted automatically."
    msg_AutoUnmountStopped:  string = "Protected drives were unmounted, but final synchronization stopped."
    msg_ChangingPassword:    string = "Rewriting the key slot..."
    msg_PasswordChanged:     string = "The vault now opens with the new password."
    msg_PasswordRemoved:     string = "The password was removed. Any selected key files are still required."
    msg_PasswordFailed:      string = "Could not change the password."
    msg_PasswordStopped:     string = "The password change stopped."
    msg_KeyFilesChanged:     string = "The vault now opens with the selected key files."
    msg_KeyFilesStopped:     string = "The key-file change stopped."
    msg_KeyFilesFailed:      string = "Could not change the key files."

    // What a failure of each [[ErrorKind]] says. The volume layer reports the kind and an
    // English diagnostic for a report; these are the sentences a reader sees instead.
    msg_ErrPasswordOrDamaged: string = "The password or key files are incorrect, or the container is damaged."     // The container did not open, and the format refuses to say which input gave up.
    msg_ErrDamaged:           string = "The container is damaged."                                                 // An open container no longer reads back what it stored.
    msg_ErrNotFound:          string = "The container could not be found."                                         // The named container or entry does not exist.
    msg_ErrAlreadyExists:     string = "A file with this name already exists."                                     // The name is taken.
    msg_ErrAccessDenied:      string = "Access to the container was refused."                                      // The entry exists and refuses the operation.
    msg_ErrReadOnly:          string = "The vault is mounted read only."                                           // The container refuses every change.
    msg_ErrSparse:            string = "The container is sparse. Convert it to a fully allocated file before opening it."
    msg_ErrDiskFull:          string = "There is no room left in the container."         // No room is left for blocks, metadata, or key slots.
    msg_ErrIo:                string = "The container could not be read or written."     // The underlying file could not be reached.
    msg_ErrInvalidRequest:    string = "The container cannot answer that request."       // The operation asked for something the container refuses outright.
}

private const FrenchStringsName = "lang/fr/vault.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/vault.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of Swag Vault in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the Swag Vault string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "vault")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
