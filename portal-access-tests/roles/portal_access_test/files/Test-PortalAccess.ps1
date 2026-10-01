# Logs one user into one portal through Keycloak and opens every dashboard link,
# the way a browser on this Windows host would. Read-only apart from the login POST.
# Runs under Windows PowerShell 5.1 (ansible.windows.win_powershell default).
param(
    [Parameter(Mandatory)] [string] $PortalUrl,
    [Parameter(Mandatory)] [string] $KeycloakHost,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [Parameter(Mandatory)] [object[]] $Links,
    [int] $TimeoutSec = 20,
    [bool] $CheckVisibility = $true
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Ansible.Changed = $false
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Invoke-Hop {
    param([string] $Uri, [string] $Method = 'GET', $Body = $null)
    $p = @{ Uri = $Uri; Method = $Method; WebSession = $session; UseBasicParsing = $true;
            MaximumRedirection = 15; TimeoutSec = $TimeoutSec }
    if ($null -ne $Body) { $p.Body = $Body; $p.ContentType = 'application/x-www-form-urlencoded' }
    try {
        $r = Invoke-WebRequest @p
        return @{ code = [int]$r.StatusCode; url = $r.BaseResponse.ResponseUri.AbsoluteUri; content = [string]$r.Content }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) { return @{ code = [int]$resp.StatusCode; url = $resp.ResponseUri.AbsoluteUri; content = '' } }
        return @{ code = 0; url = ''; content = ''; error = $_.Exception.Message }
    }
}

function Get-UriHost([string] $u) { if ($u) { ([Uri]$u).Host } else { '' } }

# 1. Open the portal: expect to land on the Keycloak login page
$open = Invoke-Hop -Uri $PortalUrl
$viaKeycloak = (Get-UriHost $open.url) -eq $KeycloakHost
$action = ''
if ($open.content -match '<form[^>]*id="kc-form-login"[^>]*>') {
    if ($Matches[0] -match 'action="([^"]+)"') { $action = [System.Net.WebUtility]::HtmlDecode($Matches[1]) }
}

# 2. Submit credentials to Keycloak
$post = @{ code = 0; url = ''; content = '' }
if ($action) {
    $post = Invoke-Hop -Uri $action -Method 'POST' -Body @{ username = $Username; password = $Password; credentialId = '' }
}
$loginOk = ($post.code -ge 200 -and $post.code -lt 300 -and (Get-UriHost $post.url) -ne $KeycloakHost)

# 3. Open every dashboard link with the same session
$linkResults = @()
if ($loginOk) {
    foreach ($l in $Links) {
        $r = Invoke-Hop -Uri $l.url
        $match = if ($l.visible_match) { $l.visible_match } else { $l.url }
        $linkResults += @{
            name      = $l.name
            code      = $r.code
            final_url = $r.url
            visible   = if ($CheckVisibility) { $post.content.Contains($match) } else { $null }
        }
    }
}

$Ansible.Result = @{
    open_code    = $open.code
    via_keycloak = $viaKeycloak
    form_found   = [bool]$action
    login_ok     = $loginOk
    login_detail = "portal -> HTTP $($open.code) at $(if ($open.url) { $open.url } else { 'no response' }); after login -> HTTP $($post.code) at $($post.url)"
    links        = $linkResults
}
