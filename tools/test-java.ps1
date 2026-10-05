$ErrorActionPreference = 'Stop'
$TaskRepo = Split-Path -Parent $PSScriptRoot
$TaskClasses = Join-Path $TaskRepo 'test-classes'
New-Item -ItemType Directory -Force -Path $TaskClasses | Out-Null
$TaskJavac = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/javac.exe' } else { 'javac' }
$TaskJava = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java.exe' } else { 'java' }
$TaskPackage = Join-Path $TaskRepo 'app/src/main/java/com/codex/minifire/compatlab'
$TaskFiles = @('HookPolicy.java','SettingsSelector.java','DiagnosticText.java') | ForEach-Object { Join-Path $TaskPackage $_ }
$TaskTests = @('HookPolicyTest','SettingsSelectorTest','DiagnosticTextTest','SimpleToggleTest','LogLinesTest')
$TaskFiles += $TaskTests | ForEach-Object { Join-Path $TaskRepo ('tests/' + $_ + '.java') }
& $TaskJavac -encoding UTF-8 -d $TaskClasses @TaskFiles
if ($LASTEXITCODE -ne 0) { throw 'Java test compilation failed' }
foreach ($TaskTest in $TaskTests) {
    & $TaskJava -cp $TaskClasses $TaskTest
    if ($LASTEXITCODE -ne 0) { throw ('Test failed: ' + $TaskTest) }
}
