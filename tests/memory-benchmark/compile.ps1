param(
    [string]$Revision = 'working',
    [string]$SdkPath = '',
    [string]$SigningKey = ''
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $SdkPath) {
    $SdkPath = (Get-Content "$env:APPDATA/Garmin/ConnectIQ/current-sdk.cfg").Trim()
}
if (-not $SigningKey) { $SigningKey = Join-Path $repo 'developer_key' }
if (-not (Test-Path -LiteralPath $SigningKey)) { throw 'Supply a local Connect IQ signing key with -SigningKey.' }
& node (Join-Path $PSScriptRoot 'prepare.cjs') $Revision
if ($LASTEXITCODE) { throw 'Benchmark generation failed' }
$kind = if ($Revision -eq 'working') { 'feature' } else { 'upstream' }
$buildDir = Join-Path $repo "bin/memory-benchmark/$kind"
foreach ($device in @('instinct2', 'fenix9pro47mm')) {
    $log = Join-Path $buildDir "$device-build.log"
    & java -Xms512m '-Dfile.encoding=UTF-8' -jar "$SdkPath/bin/monkeybrains.jar" `
        -f (Join-Path $buildDir 'benchmark.jungle') -o (Join-Path $buildDir "$device.prg") `
        -y $SigningKey -d $device -r --build-stats 0 -w 2>&1 | Set-Content $log
    if ($LASTEXITCODE) { Get-Content $log -Tail 20; throw "Compilation failed: $kind $device" }
    Write-Output "Built $kind $device"
}
