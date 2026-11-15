<#
  03-helpdesk-scenarios.ps1
  Common AD help-desk / IT admin tasks for corp.purbo.lab.
  Run on DC01 in PowerShell as Administrator.

  These are the day-to-day identity tasks a help-desk / sysadmin handles:
  offboarding a leaver, onboarding a new hire, unlocking + resetting an
  account, and processing an access-change request.

  Each function is self-contained. Dot-source this file, then call them:
    . .\03-helpdesk-scenarios.ps1
    Offboard-User   -Sam lmitchell -Group HR-Users
    Onboard-User    -First Priya -Last Shah -Department IT -Title "Help Desk Technician"
    Reset-UserLogin -Sam ajohnson
    Grant-Access    -Sam ajohnson -Group Finance-Users
#>

Import-Module ActiveDirectory

$domainDN  = "DC=corp,DC=purbo,DC=lab"
$upnSuffix = "corp.purbo.lab"

# --- Scenario 1: Offboard a leaver -------------------------------------------
# Best practice: DISABLE, don't delete. Keep the account for audit, kill access
# instantly, stamp why/when, strip group access, park it in Disabled Users.
function Offboard-User {
    param([Parameter(Mandatory)][string]$Sam, [string]$Group)

    Disable-ADAccount -Identity $Sam
    Set-ADUser -Identity $Sam -Description "Offboarded $(Get-Date -Format 'yyyy-MM-dd') - left company"
    if ($Group) { Remove-ADGroupMember -Identity $Group -Members $Sam -Confirm:$false }
    Get-ADUser $Sam | Move-ADObject -TargetPath "OU=Disabled Users,OU=Corp,$domainDN"

    Write-Host "Offboarded $Sam" -ForegroundColor Cyan
    Get-ADUser $Sam -Properties Enabled, Description | Select-Object Name, Enabled, Description
}

# --- Scenario 2: Onboard a new hire ------------------------------------------
# Creates the account in the right department OU + group, forces a day-one
# password change. Password is typed at runtime, never stored.
function Onboard-User {
    param(
        [Parameter(Mandatory)][string]$First,
        [Parameter(Mandatory)][string]$Last,
        [Parameter(Mandatory)][ValidateSet('IT','HR','Finance','Sales')][string]$Department,
        [Parameter(Mandatory)][string]$Title
    )
    $sam  = ($First.Substring(0,1) + $Last).ToLower() -replace '[^a-z0-9]',''
    $pass = Read-Host -AsSecureString "Temporary password for $sam"

    New-ADUser -Name "$First $Last" -GivenName $First -Surname $Last `
        -SamAccountName $sam -UserPrincipalName "$sam@$upnSuffix" `
        -Department $Department -Title $Title `
        -Path "OU=$Department,OU=Corp,$domainDN" `
        -AccountPassword $pass -ChangePasswordAtLogon $true -Enabled $true

    Add-ADGroupMember -Identity "$Department-Users" -Members $sam
    Write-Host "Onboarded $sam -> $Department" -ForegroundColor Green
    Get-ADUser $sam -Properties Department, Title | Select-Object Name, SamAccountName, Department, Title
}

# --- Scenario 3: Unlock + reset a locked-out account -------------------------
# The classic "I'm locked out / forgot my password" ticket.
function Reset-UserLogin {
    param([Parameter(Mandatory)][string]$Sam)
    $pass = Read-Host -AsSecureString "New password for $Sam"

    Unlock-ADAccount -Identity $Sam
    Set-ADAccountPassword -Identity $Sam -NewPassword $pass -Reset
    Set-ADUser -Identity $Sam -ChangePasswordAtLogon $true   # make them set their own next login

    Write-Host "Unlocked + reset $Sam" -ForegroundColor Cyan
    Get-ADUser $Sam -Properties LockedOut | Select-Object Name, LockedOut
}

# --- Scenario 4: Access-change request ---------------------------------------
# "Please give X access to the Finance share." = add to the group. Least
# privilege: grant the specific group, not blanket admin.
function Grant-Access {
    param([Parameter(Mandatory)][string]$Sam, [Parameter(Mandatory)][string]$Group)
    Add-ADGroupMember -Identity $Group -Members $Sam
    Write-Host "Added $Sam to $Group" -ForegroundColor Green
    Get-ADGroupMember $Group | Select-Object Name
}
