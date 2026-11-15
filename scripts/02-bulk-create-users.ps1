<#
  02-bulk-create-users.ps1
  Creates AD users from a CSV and adds each to their department group.
  Run on DC01 in PowerShell as Administrator, after 01-create-structure.ps1.

  The temporary password is typed in at runtime, so it is never stored
  in this script or committed to GitHub. Safe to re-run: existing users
  are skipped, so adding rows to the CSV and running again just onboards
  the new people.

  Usage:
    .\02-bulk-create-users.ps1
    .\02-bulk-create-users.ps1 -CsvPath "C:\Scripts\new-hires.csv"
#>
param(
    [string]$CsvPath = "C:\Scripts\users.csv"
)

Import-Module ActiveDirectory

$domainDN  = "DC=corp,DC=purbo,DC=lab"
$upnSuffix = "corp.purbo.lab"
$tempPass  = Read-Host -AsSecureString "Temporary password for new users"

$created = 0; $skipped = 0; $failed = 0

foreach ($u in Import-Csv $CsvPath) {

    # Username = first initial + last name, lowercase.  Ava Johnson -> ajohnson
    $sam = ($u.FirstName.Substring(0,1) + $u.LastName).ToLower() -replace '[^a-z0-9]',''

    # Skip if the account already exists (makes the script safe to re-run)
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "SKIP   $sam already exists" -ForegroundColor Yellow
        $skipped++; continue
    }

    try {
        New-ADUser `
            -Name                  "$($u.FirstName) $($u.LastName)" `
            -GivenName             $u.FirstName `
            -Surname               $u.LastName `
            -SamAccountName        $sam `
            -UserPrincipalName     "$sam@$upnSuffix" `
            -Department            $u.Department `
            -Title                 $u.Title `
            -Path                  "OU=$($u.Department),OU=Corp,$domainDN" `
            -AccountPassword       $tempPass `
            -ChangePasswordAtLogon $true `
            -Enabled               $true `
            -ErrorAction           Stop

        Add-ADGroupMember -Identity "$($u.Department)-Users" -Members $sam
        Write-Host "OK     $sam -> $($u.Department)" -ForegroundColor Green
        $created++
    }
    catch {
        Write-Host "FAIL   $sam : $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`nDone.  Created: $created   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
