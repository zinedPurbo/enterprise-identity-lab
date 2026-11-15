# Enterprise Identity Lab — Build Guide

Active Directory, Group Policy and PowerShell automation in Azure, with an optional
security phase (hardening, auditing and detection).

**Domain:** `corp.purbo.lab`  ·  **DC IP:** `10.0.0.4`  ·  **Resource group:** `rg-identity-lab`

> Keep a notes file open the whole time. Write down every error and how you fixed it —
> that becomes the "What I learned" section that interviewers care about most.

**How to use this guide:** do one phase per sitting, take the 📸 screenshots as you go,
and tick the boxes. ⚠️ marks the spots where most people get stuck.

---

## Checklist

- [ ] Phase 0 — Azure account + cost safety
- [ ] Phase 1 — Network (VNet)
- [ ] Phase 2 — Domain controller VM
- [ ] Phase 3 — Install AD + create the domain
- [ ] Phase 4 — OUs and groups
- [ ] Phase 5 — Bulk user script (50 users)
- [ ] Phase 6 — Department file shares
- [ ] Phase 7 — Group Policy
- [ ] Phase 8 — Client VM + domain join
- [ ] Phase 9 — Help-desk tickets
- [ ] Phase 10 — GitHub + cleanup
- [ ] Phase 11 — Security add-on (optional but recommended)

---

# Phase 0 — Azure account and cost safety (30 min)

1. Activate **Azure for Students** at `azure.microsoft.com/free/students`, signing in with your
   **student email**. It grants free credit and (at the time of writing) needs no card.
2. Open the **Azure Portal**: `portal.azure.com`.
3. **Create a resource group** — a folder that holds everything, so you can delete it all at the end:
   - Search **Resource groups** → **Create**
   - Name: `rg-identity-lab`
   - Region: the one closest to you. **Use the same region for everything.**
4. **Set a budget alert** so there are no surprises:
   - Search **Cost Management** → **Budgets** → **Add**
   - Amount `$20`, alerts at 50% / 80% / 100%, to your email.
5. **Install an RDP client on your Mac:** **Windows App** (formerly Microsoft Remote Desktop),
   from the Mac App Store. This is how you'll control the VMs.

📸 Resource group created; budget alert set.

---

# Phase 1 — Network (20 min)

1. Search **Virtual networks** → **Create**:
   - Resource group `rg-identity-lab`, Name `vnet-corp`
   - Address space `10.0.0.0/16`
   - Subnet `snet-servers` = `10.0.0.0/24`
2. Leave DNS as **Default** for now (you set it to the DC in Phase 3).

📸 VNet overview.

---

# Phase 2 — Domain controller VM (30 min)

1. Search **Virtual machines** → **Create** → **Azure virtual machine**:

   | Setting | Value |
   |---|---|
   | Resource group | `rg-identity-lab` |
   | Name | `DC01` |
   | Image | **Windows Server 2022 Datacenter: Azure Edition** (or 2025) |
   | Size | **B2s** (2 vCPU, 4 GB). Check the hourly price shown |
   | Admin username | e.g. `corpadmin` (not "admin"/"administrator" — Azure blocks them) |
   | Password | Strong; save in your password manager. **This becomes the domain admin** |
   | Public inbound ports | **None** (you add a safe rule below) |

2. **Networking tab:** VNet `vnet-corp`, subnet `snet-servers`, new Public IP.
3. **Management tab:** enable **auto-shutdown** (e.g. 23:00 your time).
4. **Review + create** (~5 min).

### Give the DC a fixed private IP
A DC's IP must never change — every machine finds the domain through it.
1. `DC01` → **Networking** → the network interface → **IP configurations** → `ipconfig1`.
2. Private IP → **Static** → `10.0.0.4` → Save.

> ⚠️ Set the static IP **in Azure**, not inside Windows. Leave the Windows adapter on automatic
> (DHCP). Setting a static IP inside an Azure VM can cut you off from it.

### Allow RDP from your IP only
1. `DC01` → **Networking** → **Add inbound port rule**.
2. Source **My IP address**, Service **RDP** (3389), Action Allow, Name `Allow-RDP-MyIP`.

> ⚠️ Never set the source to "Any" — bots scan the internet for open RDP within minutes.
> If your home IP changes later, edit this rule.

### Connect
`DC01` → **Overview** → copy the **public IP** → in **Windows App**, Add PC → connect as
`corpadmin`.

📸 VM overview (size, static private IP, auto-shutdown); the NSG rule sourced to your IP.

---

# Phase 3 — Install AD and create the domain (30 min)

Run everything below in **PowerShell as Administrator, on DC01**.

### Install the AD role
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
```

### Promote the server to a domain controller
```powershell
Install-ADDSForest `
  -DomainName "corp.purbo.lab" `
  -DomainNetbiosName "CORP" `
  -InstallDns `
  -SafeModeAdministratorPassword (Read-Host -AsSecureString "DSRM password")
```
| Piece | Meaning |
|---|---|
| `Install-ADDSForest` | Create a new forest (the top-level container) |
| `-DomainName` | The full domain name |
| `-DomainNetbiosName` | Short name, so logins read `CORP\username` |
| `-InstallDns` | Install DNS too (AD needs it) |
| `-SafeModeAdministratorPassword` | Recovery password — save it in your password manager |

The server **reboots automatically**. Reconnect after 5–10 min and log in as **`CORP\corpadmin`**.

### Point the VNet's DNS at the DC
Without this, other machines can't find the domain.
1. Azure → `vnet-corp` → **DNS servers** → **Custom** → `10.0.0.4` → Save.
2. **Restart DC01** from the portal so it picks up the setting.

> ⚠️ This is the step almost everyone forgets. If the client can't join later, check this first.

### Verify
```powershell
Get-ADDomain
Get-Service NTDS, DNS
```
Both services **Running**; `Get-ADDomain` shows `corp.purbo.lab`.

📸 `Get-ADDomain` output; Server Manager showing AD DS + DNS.

---

# Phase 4 — OUs and groups (20 min)

**OUs (Organizational Units)** are folders in AD; you apply different policies to each.

Copy `scripts/01-create-structure.ps1` to `C:\Scripts\` on DC01 and run it. Result:
```
corp.purbo.lab
└── Corp
    ├── IT        (group: IT-Users)
    ├── HR        (group: HR-Users)
    ├── Finance   (group: Finance-Users)
    ├── Sales     (group: Sales-Users)
    ├── Workstations
    └── Disabled Users
```

📸 Active Directory Users and Computers (ADUC) showing the OU tree.

---

# Phase 5 — Bulk user script, 50 users (2–3 h)

1. Copy `scripts/users.csv` and `scripts/02-bulk-create-users.ps1` to `C:\Scripts\` on DC01.
2. If scripts are blocked, run once:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. Run it:
   ```powershell
   cd C:\Scripts
   .\02-bulk-create-users.ps1
   ```
   It asks for one temporary password (e.g. `Welcome-2026!x`), creates the users, puts each in
   the right OU and group, and forces a password change at first login.

4. Verify:
   ```powershell
   Get-ADUser -Filter * -SearchBase "OU=Corp,DC=corp,DC=purbo,DC=lab" | Measure-Object
   Get-ADGroupMember "HR-Users" | Select-Object Name
   ```

> ⚠️ Common issues:
> - **Password too weak** → every user fails. Use something like `Welcome-2026!x`.
> - **Duplicate username** (same first-initial + surname) → the second is skipped. The CSV here
>   is already collision-free; worth a sentence in your write-up about how you'd handle it (add a number).
> - **Execution policy error** → run the `Set-ExecutionPolicy` line above.

📸 The script's Created/Skipped/Failed summary; ADUC showing users in a department OU; a group's members.

---

# Phase 6 — Department file shares (1 h)

On DC01, PowerShell as Administrator:
```powershell
$depts = "IT","HR","Finance","Sales"
foreach ($d in $depts) {
    $path = "C:\Shares\$d"
    New-Item -ItemType Directory -Path $path -Force | Out-Null

    # Share permission: the department group can change files
    New-SmbShare -Name $d -Path $path -ChangeAccess "CORP\$d-Users" -FullAccess "CORP\Domain Admins"

    # NTFS permission: give the group Modify, drop inherited "Users" access
    icacls $path /inheritance:d
    icacls $path /remove "BUILTIN\Users"
    icacls $path /grant "CORP\$d-Users:(OI)(CI)M"
}
```
Two layers of permissions — Windows applies the **stricter**:
| Layer | Applies when | Set with |
|---|---|---|
| Share | Over the network (`\\DC01\HR`) | `New-SmbShare` |
| NTFS | Always, on the folder | `icacls` |

Result: HR users can open `\\DC01\HR`; Sales users can't. You'll test this in Phase 9.

> Note: in a real company the shares live on a separate file server, not the DC. Fine for a lab —
> just say so in the README.

📸 `Get-SmbShare`; a folder's Security tab showing the department group.

---

# Phase 7 — Group Policy (2–3 h)

Open **Group Policy Management** (Server Manager → Tools).

**Three rules that save hours:**
1. **Domain password/lockout policy only works in a GPO linked at the domain level** (the Default
   Domain Policy). Linked to an OU it does nothing for domain accounts.
2. **You can't link a GPO to the built-in "Computers"/"Users" containers** — they aren't OUs.
   That's why you made a **Workstations** OU and will move the client into it.
3. **Computer Configuration → computers; User Configuration → users.** A user setting applied where
   there are only computers does nothing.

### GPO 1 — Password + lockout (edit **Default Domain Policy**)
Computer Configuration → Policies → Windows Settings → Security Settings → **Account Policies**:
| Setting | Value |
|---|---|
| Minimum password length | 12 |
| Password must meet complexity requirements | Enabled |
| Maximum password age | 90 days |
| Account lockout threshold | 5 |
| Account lockout duration | 15 min |
| Reset lockout counter after | 15 min |

### GPO 2 — Block USB storage (link to **Workstations**)
New GPO `Block-USB-Storage` → Computer Configuration → Policies → Administrative Templates → System →
**Removable Storage Access** → "All Removable Storage classes: Deny all access" = Enabled.

> You can't plug a USB stick into an Azure VM. Prove the policy **applied** with `gpresult` (Phase 8)
> and say so honestly. Or swap it for "block Control Panel" for HR, which you can fully test.

### GPO 3 — Mapped drive per department (one GPO per dept, linked to its OU)
Example HR: new GPO `Map-Drive-HR` on the HR OU → **User** Configuration → Preferences → Windows
Settings → **Drive Maps** → New → Mapped Drive: Action **Update**, Location `\\DC01\HR`, Reconnect ✔,
Label `HR Shared`, Drive **H:**. Repeat: IT=`I:`, Finance=`F:`, Sales=`S:`.

### GPO 4 — Company wallpaper
1. `C:\Shares\Wallpaper\corp.jpg`, shared as `Wallpaper` (Read for `Domain Users`).
2. New GPO `Corp-Wallpaper` on the **Corp** OU → User Configuration → Policies → Administrative
   Templates → Desktop → Desktop → **Desktop Wallpaper** = Enabled, Name `\\DC01\Wallpaper\corp.jpg`,
   Style Fill.

📸 The GPO tree (what's linked where); each GPO's settings (right-click → Save Report, or the Settings tab).

---

# Phase 8 — Client VM and domain join (1–2 h)

### Create the client
Same as Phase 2 with:
- Name `CLIENT01`
- Image: **Windows 11 Pro/Enterprise** *if* your student benefits cover the licence (tick the
  licence box only if eligible); **otherwise Windows Server 2022** — joining and policies work the same.
- Same VNet/subnet, RDP from your IP only, auto-shutdown on.

### Check it can see the DC (on CLIENT01)
```powershell
ipconfig /all                         # DNS Servers must show 10.0.0.4
nslookup corp.purbo.lab               # must answer with 10.0.0.4
Test-NetConnection 10.0.0.4 -Port 389 # must be True
```
> ⚠️ If DNS isn't `10.0.0.4`, you skipped the VNet DNS step or the VM was made before it. Restart CLIENT01.

### Join the domain
```powershell
Add-Computer -DomainName "corp.purbo.lab" -Credential "CORP\corpadmin" -Restart
```

### Move it into Workstations (on DC01)
```powershell
Get-ADComputer CLIENT01 | Move-ADObject -TargetPath "OU=Workstations,OU=Corp,DC=corp,DC=purbo,DC=lab"
```
Otherwise it sits in the default Computers container and the USB GPO never applies.

### Let domain users RDP in (on CLIENT01, as admin)
```powershell
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "CORP\Domain Users"
```
(Only needed because you reach the client over RDP; note it's a cloud-lab quirk.)

### Test as a real user
1. RDP to CLIENT01 as `CORP\ajohnson` with the temp password → it forces a password change ✔
2. Check the **H:** drive and the **wallpaper**.
3. See what applied:
   ```powershell
   gpupdate /force
   gpresult /r
   ```

> ⚠️ GPO didn't apply? Check: linked to the right OU? user vs computer setting? client in Workstations?
> did you `gpupdate /force` or re-login? (Drive maps apply at login.)

📸 Domain join success; client in Workstations; H: drive in Explorer; `gpresult /r` listing your GPOs.

---

# Phase 9 — Help-desk tickets (2–3 h)

For each: **create the problem → fix it → screenshot → write it up.**

| # | Ticket | Create the problem | Fix (on DC01) |
|---|---|---|---|
| 1 | Forgot password | — | `Set-ADAccountPassword ajohnson -Reset -NewPassword (Read-Host -AsSecureString)` then `Set-ADUser ajohnson -ChangePasswordAtLogon $true` |
| 2 | Locked out | Log in wrong 5× | `Search-ADAccount -LockedOut`; `Unlock-ADAccount ajohnson` |
| 3 | Can't open HR drive | Remove user from HR-Users | `Get-ADPrincipalGroupMembership <user>`; `Add-ADGroupMember HR-Users <user>` (re-login) |
| 4 | New hire Monday | — | Add a CSV row, re-run `02-bulk-create-users.ps1` |
| 5 | Employee left | — | `Disable-ADAccount <user>` → move to Disabled Users OU → remove from groups |
| 6 (bonus) | Policy didn't apply | Move CLIENT01 back to Computers | Diagnose with `gpresult /r`, move to Workstations, `gpupdate /force` |

**Write-up template** (`docs/tickets.md`):
```markdown
## TKT-002 — Account locked out
- Reported by: Ava Johnson (HR)
- Issue: "I can't log in, it says my account is locked."
- Priority: High (user can't work)
- Investigation: Search-ADAccount -LockedOut showed ajohnson locked at 10:42
  after 5 failed attempts (policy: 5 / 15 min).
- Resolution: Verified identity, ran Unlock-ADAccount ajohnson, user logged in.
- Root cause: User typed the old password after a reset.
- Prevention: Reminded user; lockout policy working as designed.
- Evidence: ![](../screenshots/t02-locked-out.png)
```

📸 Each ticket: before (error) and after (fixed).

---

# Phase 10 — GitHub and cleanup

### Repo layout
```
enterprise-identity-lab/
├── README.md               overview, diagram, "what I learned"
├── scripts/                01-create-structure.ps1, 02-bulk-create-users.ps1, users.csv
├── docs/                   setup.md, group-policy.md, tickets.md
├── diagrams/network.png
└── screenshots/
```

### Before pushing — secrets check
- **No passwords** in any file (the script asks at runtime — good).
- **No public IPs** in screenshots (crop/blur).
- **No Azure subscription ID** in screenshots.

### Save credit
- **Stop both VMs** when not working (auto-shutdown covers forgotten nights).
- When the project is **finished and fully screenshotted**, delete the resource group
  `rg-identity-lab` to stop all charges. Deleting can't be undone, so capture everything first.

---

# Phase 11 — Security add-on (optional, recommended) — 6–10 h

Turns an IT project into one that also speaks to security/SOC/IAM roles.
Everything stays **inside your own lab**. Four parts: **harden → log → test → detect.**

## Part A — Harden (2 h)

**Separate admin accounts (least privilege):**
```powershell
New-ADUser -Name "Noah Brown (Admin)" -SamAccountName "adm-nbrown" `
  -UserPrincipalName "adm-nbrown@corp.purbo.lab" -Path "OU=IT,OU=Corp,DC=corp,DC=purbo,DC=lab" `
  -AccountPassword (Read-Host -AsSecureString) -Enabled $true
Add-ADGroupMember "Domain Admins" -Members "adm-nbrown"
```
**Tougher rules for admins (fine-grained password policy):**
```powershell
New-ADFineGrainedPasswordPolicy -Name "Admins-PSO" -Precedence 10 `
  -MinPasswordLength 16 -ComplexityEnabled $true -LockoutThreshold 3 `
  -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
Add-ADFineGrainedPasswordPolicySubject "Admins-PSO" -Subjects "Domain Admins"
```
**Windows LAPS (unique local admin password per PC):**
```powershell
Update-LapsADSchema
Set-LapsADComputerSelfPermission -Identity "OU=Workstations,OU=Corp,DC=corp,DC=purbo,DC=lab"
# then a GPO on Workstations: System > LAPS > "Configure password backup directory" = Active Directory
Get-LapsADPassword CLIENT01 -AsPlainText
```
**Protected Users** (blocks weak, easily-stolen sign-in methods): `Add-ADGroupMember "Protected Users" -Members "adm-nbrown"`

## Part B — Turn on security auditing (1 h)
New GPO `Audit-Policy`, linked to the **Domain Controllers** OU (and Workstations) →
Computer Configuration → Policies → Windows Settings → Security Settings →
**Advanced Audit Policy Configuration**:
| Category → Setting | Value | So you can see |
|---|---|---|
| Account Logon → Credential Validation | Success, Failure | failed passwords |
| Account Logon → Kerberos Authentication Service | Success, Failure | logon failures |
| Logon/Logoff → Logon | Success, Failure | 4624 / 4625 |
| Logon/Logoff → Account Lockout | Success | 4740 |
| Account Management → User Account Management | Success, Failure | new accounts (4720) |
| Account Management → Security Group Management | Success, Failure | group changes (4728/4732) |

```powershell
gpupdate /force
auditpol /get /category:"Account Logon","Account Management"
```

**Event IDs a SOC analyst must know:** 4624 logon · 4625 failed logon · 4740 lockout ·
4720 user created · 4728/4732 added to a security group · 4769 Kerberos service ticket.

## Part C — Safely test detections (2 h) — Atomic Red Team
Use **Atomic Red Team** (Red Canary), the standard open-source harness of small, reversible tests
mapped to MITRE. It keeps the work defensive: run a known test against **your own lab**, confirm the
log caught it, then clean up. **Only against your lab**, and keep Microsoft's Azure pen-test rules linked in your notes.

Install on CLIENT01:
```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
Install-AtomicRedTeam -getAtomics
```
Always three steps — read first, run, clean up:
```powershell
Invoke-AtomicTest T1136.001 -ShowDetails   # read what it does FIRST
Invoke-AtomicTest T1136.001                # run it
Invoke-AtomicTest T1136.001 -Cleanup       # undo it
```
Techniques that fit an AD lab: **T1136.001** create account (4720) · **T1098** group change (4728/4732) ·
**T1087** account discovery · **T1201** password-policy discovery.

## Part D — Detect and write it up (2–3 h)

**Option 1 — PowerShell hunting** (simplest):
```powershell
# Newly created accounts
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4720} -MaxEvents 20 |
  Select-Object TimeCreated, @{N='NewAccount';E={$_.Properties[0].Value}}

# Added to a group (watch Domain Admins)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4728,4732} -MaxEvents 20 |
  Select-Object TimeCreated, Message

# Failed-logon spikes in the last hour, by targeted account
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddHours(-1)} |
  Group-Object { $_.Properties[5].Value } | Sort-Object Count -Descending |
  Select-Object Count, Name
```

**Option 2 — Azure Sentinel** (stronger; a second SIEM on your CV):
Create a Log Analytics workspace → connect the VMs with the Azure Monitor Agent + **Security Events**
connector (forward only what you need) → write KQL analytics rules, e.g.:
```kql
SecurityEvent
| where EventID in (4728, 4732)
| where TargetUserName == "Domain Admins"
| project TimeGenerated, SubjectUserName, MemberName
```
> ⚠️ Sentinel bills by data ingested. Forward only the needed events, use the free trial, delete the
> workspace when done.

**Detection write-up** (`docs/detections.md`):
```markdown
## Detection: Suspicious new Domain Admin
- Technique: MITRE T1098 (Account Manipulation)
- Test: Invoke-AtomicTest T1098 on CLIENT01 (lab only), then -Cleanup
- Log source: Security event 4728 on DC01
- What I saw: account added to Domain Admins at 14:03
- Why it matters: attackers add a backdoor admin for persistence
- Detection: KQL / PowerShell on EventID 4728 where group = Domain Admins
- Response: verify it was authorized; if not, remove the member and disable the account
- Evidence: ![](../screenshots/detect-new-admin.png)
```

---

## Suggested schedule
| Day | Phases | Time |
|---|---|---|
| 1 | 0–3  Azure, network, DC, domain | ~2 h |
| 2 | 4–5  OUs, groups, bulk users | ~3 h |
| 3 | 6–7  shares, Group Policy | ~3 h |
| 4 | 8    client, domain join, testing | ~2 h |
| 5 | 9–10 tickets, write-up, GitHub | ~4 h |
| 6 | 11   security add-on (optional) | ~6–10 h |

## Resume bullets (fill in your real numbers after building)
- Built a Windows Server Active Directory domain in Azure with department OUs, security groups, DNS,
  and Group Policy (password, lockout, USB, mapped drives).
- Automated creation of 50 users from CSV with PowerShell, including group assignment and forced
  password change.
- Hardened the domain (least privilege, Windows LAPS, fine-grained password policy), enabled security
  auditing, and wrote detections for account creation and privilege-escalation events.
- Resolved and documented 6 help-desk scenarios (lockouts, resets, permissions, on/offboarding).

> Two caveats: Azure renames portal menus occasionally — search the feature name if a label differs.
> And check the VM price shown for your region before clicking Create.
