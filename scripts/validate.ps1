<#
.SYNOPSIS
    Validates private connectivity from a Windows client to a Neo4j Aura
    instance reached over Private Service Connect.

.DESCRIPTION
    Runs three TCP reachability checks (7687, 443, 7474) and one DNS assertion
    against the provided instance hostname. Exits 0 if all checks pass, 1 if
    any check fails. Prints a summary table at the end.

.PARAMETER Neo4jHost
    Full instance hostname, e.g. abc1.production-orch-0042.neo4j.io.

.PARAMETER ExpectedPscIp
    The PSC endpoint internal IP that DNS must resolve to. Use the value of the
    psc_endpoint_ip terraform output.

.EXAMPLE
    .\validate.ps1 -Neo4jHost abc1.production-orch-0042.neo4j.io -ExpectedPscIp 10.10.1.5
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Neo4jHost,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPscIp
)

$ErrorActionPreference = "Continue"
$results = New-Object System.Collections.Generic.List[object]

# --- DNS resolution check ---
$resolvedIp = $null
try {
    $dns = Resolve-DnsName -Name $Neo4jHost -Type A -ErrorAction Stop
    $aRecord = $dns | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
    if ($null -ne $aRecord) {
        $resolvedIp = $aRecord.IPAddress
    }

    if ($resolvedIp -eq $ExpectedPscIp) {
        $results.Add([PSCustomObject]@{
                Check   = "DNS A record"
                Status  = "PASS"
                Details = "$Neo4jHost -> $resolvedIp"
            }) | Out-Null
    }
    else {
        $results.Add([PSCustomObject]@{
                Check   = "DNS A record"
                Status  = "FAIL"
                Details = "Resolved=$resolvedIp Expected=$ExpectedPscIp"
            }) | Out-Null
    }
}
catch {
    $results.Add([PSCustomObject]@{
            Check   = "DNS A record"
            Status  = "FAIL"
            Details = $_.Exception.Message
        }) | Out-Null
}

# --- Port reachability checks ---
# 443=HTTPS, 7687=Bolt, 7474=Browser, 8491=Graph Analytics (GDS).
foreach ($port in 7687, 443, 7474, 8491) {
    try {
        $test = Test-NetConnection -ComputerName $Neo4jHost -Port $port -WarningAction SilentlyContinue -InformationLevel Detailed
        if ($test.TcpTestSucceeded) {
            $results.Add([PSCustomObject]@{
                    Check   = "TCP $port"
                    Status  = "PASS"
                    Details = "RemoteAddress=$($test.RemoteAddress)"
                }) | Out-Null
        }
        else {
            $results.Add([PSCustomObject]@{
                    Check   = "TCP $port"
                    Status  = "FAIL"
                    Details = "TcpTestSucceeded=False RemoteAddress=$($test.RemoteAddress)"
                }) | Out-Null
        }
    }
    catch {
        $results.Add([PSCustomObject]@{
                Check   = "TCP $port"
                Status  = "FAIL"
                Details = $_.Exception.Message
            }) | Out-Null
    }
}

Write-Host ""
Write-Host "Neo4j PSC connectivity summary"
Write-Host "==============================="
Write-Host "Host         : $Neo4jHost"
Write-Host "Expected IP  : $ExpectedPscIp"
Write-Host "Resolved IP  : $resolvedIp"
Write-Host ""

$results | Format-Table -AutoSize | Out-String | Write-Host

$failed = $results | Where-Object { $_.Status -eq "FAIL" }
if ($failed.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($failed.Count) check(s) failed)" -ForegroundColor Red
    exit 1
}

Write-Host "RESULT: PASS (all checks passed)" -ForegroundColor Green
exit 0
