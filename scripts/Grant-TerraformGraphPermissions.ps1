[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [guid]$TenantId,

    # The managed identity's principal/object ID, not its client ID.
    [Parameter(Mandatory)]
    [guid]$ManagedIdentityObjectId,

    # ServicePrincipalRead is for a plan identity that only needs the
    # App Service Certificate service-principal lookup.
    [ValidateSet("Apply", "ServicePrincipalRead")]
    [string]$PermissionSet = "Apply"
)

$ErrorActionPreference = "Stop"

# Prerequisite: Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

# The administrator running this script needs consent for these delegated
# scopes and a supported Entra role to assign app roles.
if (Get-MgContext) {
    Disconnect-MgGraph
}

Connect-MgGraph `
    -TenantId $TenantId `
    -Scopes @("AppRoleAssignment.ReadWrite.All", "Application.Read.All") `
    -ContextScope Process `
    -NoWelcome

$context = Get-MgContext
if ($context.TenantId -ne $TenantId.ToString()) {
    throw "Connected to tenant $($context.TenantId), expected $TenantId."
}
$requiredScopes = @("AppRoleAssignment.ReadWrite.All", "Application.Read.All")
$missingScopes = @($requiredScopes | Where-Object { $_ -notin $context.Scopes })
if ($context.AuthType -ne "Delegated" -or $missingScopes.Count -gt 0) {
    throw "Microsoft Graph did not establish the required delegated context. AuthType='$($context.AuthType)'; missing scopes: $($missingScopes -join ', ')."
}

try {
    $managedIdentity = Get-MgServicePrincipal `
        -ServicePrincipalId $ManagedIdentityObjectId `
        -Property Id, DisplayName, ServicePrincipalType `
        -ErrorAction Stop
} catch {
    throw "Microsoft Graph could not read service principal '$ManagedIdentityObjectId'. Check the delegated Graph context and retry sign-in. Original error: $($_.Exception.Message)"
}

if (-not $managedIdentity) {
    throw "No service principal was found with object ID '$ManagedIdentityObjectId'."
}
if ($managedIdentity.ServicePrincipalType -ne "ManagedIdentity") {
    throw "Object '$ManagedIdentityObjectId' is a '$($managedIdentity.ServicePrincipalType)' service principal, not a managed identity."
}

$graph = @(
    Get-MgServicePrincipal `
        -Filter "appId eq '00000003-0000-0000-c000-000000000000'" `
        -Property Id, AppRoles
)

if ($graph.Count -ne 1) {
    throw "Could not uniquely find the Microsoft Graph service principal."
}
$graph = $graph[0]

$permissionNames = if ($PermissionSet -eq "Apply") {
    @(
        "Application.ReadWrite.All"
        "Group.ReadWrite.All"
        "AppRoleAssignment.ReadWrite.All"
        "DelegatedPermissionGrant.ReadWrite.All"
    )
} else {
    @("Application.Read.All")
}

$existingAssignments = @(
    Get-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $managedIdentity.Id `
        -All
)

foreach ($permissionName in $permissionNames) {
    $appRole = @(
        $graph.AppRoles | Where-Object {
            $_.Value -eq $permissionName -and
            $_.AllowedMemberTypes -contains "Application"
        }
    )

    if ($appRole.Count -ne 1) {
        throw "Could not uniquely find the Microsoft Graph application permission '$permissionName'."
    }
    $appRole = $appRole[0]

    $alreadyAssigned = $existingAssignments | Where-Object {
        $_.ResourceId -eq $graph.Id -and
        $_.AppRoleId -eq $appRole.Id
    }

    if ($alreadyAssigned) {
        Write-Host "Already assigned: $permissionName"
        continue
    }

    if ($PSCmdlet.ShouldProcess($managedIdentity.DisplayName, "Grant Microsoft Graph $permissionName")) {
        $body = @{
            principalId = $managedIdentity.Id
            resourceId  = $graph.Id
            appRoleId   = $appRole.Id
        }

        New-MgServicePrincipalAppRoleAssignment `
            -ServicePrincipalId $managedIdentity.Id `
            -BodyParameter $body | Out-Null

        Write-Host "Granted: $permissionName"
    }
}