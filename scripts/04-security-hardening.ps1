<#
  04-security-hardening.ps1
  Defensive hardening for corp.purbo.lab. Run on DC01 as Administrator.

  Covers three high-value, low-risk controls:
    1. Audit logging   - so logons, account changes and group changes are
                         recorded in the Security event log (detection).
    2. Admin password  - a stricter fine-grained password policy (PSO) for
       policy (PSO)      privileged accounts than for regular users.
    3. Privileged      - review who is in the sensitive groups (least
       access review     privilege / standing-access check).

  Everything here is read-or-tighten only. Nothing is deleted or attacked.
#>

Import-Module ActiveDirectory

# --- 1. Enable audit logging --------------------------------------------------
# Records: 4624 success logon, 4625 failed logon, 4720 user created,
# 4740 account locked out, 4728/4732 added to a group. These are the exact
# events a SOC (e.g. Wazuh/Sentinel) alerts on.
# Enterprise equivalent: set these in the Default Domain Controllers GPO under
# Advanced Audit Policy Configuration. auditpol applies the same settings here.
function Enable-AuditLogging {
    auditpol /set /subcategory:"Logon"                   /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff"                  /success:enable
    auditpol /set /subcategory:"User Account Management"  /success:enable /failure:enable
    auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
    Write-Host "`nAudit settings now:" -ForegroundColor Cyan
    auditpol /get /category:"Logon/Logoff","Account Management"
}

# --- 2. Stricter password policy for admins (fine-grained PSO) -----------------
# The Default Domain Policy already sets a baseline for everyone. This PSO
# applies a TOUGHER rule (longer min length, more history) to privileged
# accounts only - because admin creds are the crown jewels.
function Set-AdminPasswordPolicy {
    $name = "Admins-Strong-PSO"
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$name'" -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy -Name $name -Precedence 10 `
            -MinPasswordLength 16 -PasswordHistoryCount 24 `
            -ComplexityEnabled $true -MaxPasswordAge "60.00:00:00" `
            -LockoutThreshold 5 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
        Write-Host "Created PSO: $name" -ForegroundColor Green
    }
    # Apply it to the Domain Admins group
    Add-ADFineGrainedPasswordPolicySubject -Identity $name -Subjects "Domain Admins"
    Get-ADFineGrainedPasswordPolicy $name | Select-Object Name, Precedence, MinPasswordLength, AppliesTo
}

# --- 3. Privileged access review ---------------------------------------------
# Who holds standing admin rights? Should be a short, known list. Anything
# unexpected here is the first thing an attacker (or auditor) looks for.
function Show-PrivilegedAccess {
    foreach ($g in "Domain Admins","Enterprise Admins","Schema Admins","Administrators") {
        Write-Host "`n== $g ==" -ForegroundColor Cyan
        Get-ADGroupMember $g -ErrorAction SilentlyContinue | Select-Object Name, objectClass
    }
}
