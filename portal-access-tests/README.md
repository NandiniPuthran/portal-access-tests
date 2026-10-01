# Portal access tests (Keycloak SSO, existing users, read-only)

Logs each existing user into each portal **through Keycloak**, from the machine the
portal is meant to be used from, and checks every dashboard link against an
expected-access matrix. No user, group or Keycloak setting is changed.

| Portal | Tested from | How |
|--------|-------------|-----|
| Admin portal | server1 (Linux) | `curl` with a cookie jar (browser-like redirects + cookies) |
| User portal  | Windows server  | PowerShell `Invoke-WebRequest` with a web session |

## What each run checks, per user and portal

1. **KEYCLOAK** – opening the portal redirects to the Keycloak login form.
2. **LOGIN** – login is allowed (`all` / list) or refused (`none`) as expected.
3. **Each link** – allowed links open; every other link is refused.
   "Opens" = final HTTP 2xx and not bounced to Keycloak. With `pat_check_visibility`,
   it also flags links that are shown/hidden on the dashboard contrary to the matrix.
4. **ORIGIN** (optional) – the portal is not reachable from hosts listed in
   `must_not_be_reachable_from` (e.g. Admin portal from the Windows server).

A link that is hidden on the dashboard but still opens when requested directly is
reported as **Fail** — hiding a link is not access control.

## Setup

```bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml && ansible-vault encrypt group_vars/all/vault.yml
vi group_vars/all/main.yml      # portals, links, users and the access matrix
vi inventory/hosts.ini          # server1 and the Windows server (WinRM or SSH)
ansible-galaxy collection install ansible.windows
```

Access matrix (`pat_users[].access`): `all`, `none`, or a list of link names.
A misspelled link name stops the run in preflight.

## Run

```bash
ansible-playbook -i inventory/hosts.ini site.yml --ask-vault-pass
ansible-playbook ... --tags linux      # Admin portal only
ansible-playbook ... --tags windows    # User portal only
ansible-playbook ... --tags origin     # network-origin checks only
```

Results: `results/portal_access_<timestamp>.csv` (ID, portal, user, check, expected,
result, actual). The play fails at the end if any check failed (`pat_fail_on_findings`).

## Requirements and limits

- server1 needs `curl`; the FreeIPA CA at `pat_ca_path` (or trusted system-wide).
- The Windows server needs WinRM/SSH reachable from the controller, and the internal CA
  in its Trusted Root store.
- **Scripted login only works for username + password.** If Keycloak asks for OTP/MFA,
  terms acceptance or a password update for these users, login shows as failed.
- The login form is found by its standard id `kc-form-login`. A heavily customised login
  theme may need the regex adjusted (linux_user.yml / Test-PortalAccess.ps1).
- Visibility check searches the portal's HTML for the link URL (or `visible_match`).
  If the dashboard builds its menu with JavaScript, links will not be in the HTML — set
  `pat_check_visibility: false` and check visibility by eye; the access checks still work.
- Each run is one login per user per portal. A wrong password in the vault counts toward
  the account lockout threshold, so fix credentials before re-running repeatedly.
- Syntax-checked and the parsing/evaluation logic unit-tested; not yet run against your
  live Keycloak, portals or Windows host.
