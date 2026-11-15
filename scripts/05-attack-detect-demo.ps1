<#
  05-attack-detect-demo.ps1
  Safe brute-force simulation + detection, run on DC01 as Administrator.

  Purpose: prove the audit logging from 04-security-hardening.ps1 actually
  catches an attack. We hammer ONE lab account with wrong passwords until the
  lockout policy trips, then read the exact Security-log events it produced.

  This is defensive detection testing against the lab's OWN account. It sends
  no payload, installs nothing, and is fully reversed at the end (unlock).
  Only ever run this against an account in a lab you own.

  Events produced:
    4625 - failed logon        (each wrong password)
    4740 - account locked out  (when the threshold from GPO 1 is hit)
#>

param([string]$Target = "ajohnson", [int]$Attempts = 10)

Import-Module ActiveDirectory
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

$before = Get-Date

# --- Simulate the brute force -------------------------------------------------
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain','corp.purbo.lab')
Write-Host "Throwing $Attempts bad passwords at $Target ..." -ForegroundColor Yellow
1..$Attempts | ForEach-Object {
    [void]$ctx.ValidateCredentials($Target, "WrongPassword$_!")   # each fails -> 4625
}

Start-Sleep -Seconds 3   # let the events land

# --- Detect it ----------------------------------------------------------------
Write-Host "`n== Account state ==" -ForegroundColor Cyan
Get-ADUser $Target -Properties LockedOut, badPwdCount | Select-Object Name, LockedOut, badPwdCount

Write-Host "`n== 4625 failed logons (last few) ==" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$before} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, @{N='TargetUser';E={$_.Properties[5].Value}} | Format-Table -Auto

Write-Host "`n== 4740 account lockout ==" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740; StartTime=$before} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, @{N='LockedUser';E={$_.Properties[0].Value}} | Format-Table -Auto

# --- Clean up: restore the account -------------------------------------------
Unlock-ADAccount -Identity $Target
Write-Host "Cleanup: $Target unlocked. Demo complete." -ForegroundColor Green
