<#
  01-create-structure.ps1
  Creates the OU tree and one security group per department for corp.purbo.lab.
  Run on DC01 in PowerShell as Administrator, after the domain is created.
  Safe to re-run: skips anything that already exists.
#>

Import-Module ActiveDirectory

$domain = "DC=corp,DC=purbo,DC=lab"
$root   = "OU=Corp,$domain"
$depts  = "IT","HR","Finance","Sales"

# Top-level company OU
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Corp'" -SearchBase $domain -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "Corp" -Path $domain -ProtectedFromAccidentalDeletion $true
    Write-Host "Created OU: Corp" -ForegroundColor Green
}

# Department OUs + one security group each
foreach ($d in $depts) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$d'" -SearchBase $root -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $d -Path $root
        Write-Host "Created OU: $d" -ForegroundColor Green
    }
    if (-not (Get-ADGroup -Filter "Name -eq '$d-Users'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "$d-Users" -GroupScope Global -GroupCategory Security -Path "OU=$d,$root"
        Write-Host "Created group: $d-Users" -ForegroundColor Green
    }
}

# Extra OUs for computers and leavers
foreach ($extra in "Workstations","Disabled Users") {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$extra'" -SearchBase $root -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $extra -Path $root
        Write-Host "Created OU: $extra" -ForegroundColor Green
    }
}

Write-Host "`nStructure ready." -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * -SearchBase $root | Select-Object Name
