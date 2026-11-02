param([string]$SdkRoot=$env:ANDROID_SDK_ROOT)
$ErrorActionPreference='Stop'
if(-not $SdkRoot){$SdkRoot=Join-Path $env:USERPROFILE 'Android/Sdk'}
$TaskProject=Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskClang=Join-Path $SdkRoot 'ndk/26.3.11579264/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
if(-not(Test-Path -LiteralPath $TaskClang)){throw "Missing NDK compiler: $TaskClang"}
$TaskBuild=Join-Path $TaskProject 'build'
New-Item -ItemType Directory -Path $TaskBuild -Force | Out-Null
$TaskSaved=@{}
foreach($TaskName in @('GOOS','GOARCH','CGO_ENABLED','CC')){$TaskSaved[$TaskName]=[Environment]::GetEnvironmentVariable($TaskName,'Process')}
Push-Location (Join-Path $TaskProject 'daemon')
try{
    $env:GOOS='android';$env:GOARCH='arm64';$env:CGO_ENABLED='1'
    $env:CC='"'+$TaskClang.Replace('\','/')+'" --target=aarch64-linux-android26'
    & go build -tags netcgo -trimpath -ldflags '-s -w -linkmode=external -extldflags=-Wl,-z,max-page-size=16384' -o (Join-Path $TaskBuild 'minifire-external') .
    if($LASTEXITCODE -ne 0){throw 'Android daemon build failed'}
}finally{
    Pop-Location
    foreach($TaskName in $TaskSaved.Keys){[Environment]::SetEnvironmentVariable($TaskName,$TaskSaved[$TaskName],'Process')}
}
& uv run python (Join-Path $TaskProject 'tools/package.py') (Join-Path $TaskProject '../../outputs/Minifire-External-Root-1.0.6-candidate.zip')
if($LASTEXITCODE -ne 0){throw 'Root module packaging failed'}
