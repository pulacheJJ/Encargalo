param(
 [Parameter(Mandatory=$true)][string]$Serial,
 [string]$AndroidSdk='D:\desarrollo\android-sdk'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$package='pe.edu.unp.encargalo'
$adb=Join-Path $AndroidSdk 'platform-tools/adb.exe'
$aapt=Join-Path $AndroidSdk 'build-tools/34.0.0/aapt.exe'
$apksigner=Join-Path $AndroidSdk 'build-tools/34.0.0/apksigner.bat'
$apk=Join-Path $root 'apk/Encargalo.apk'
$manifest=Get-Content -Raw (Join-Path (Split-Path $root -Parent) 'encargalo_documentacion/evidencias/compilacion/MANIFIESTO.json') | ConvertFrom-Json
if(!$manifest.cloudConfigured -or !$manifest.deployed){throw 'Se requiere la entrega conectada al backend desplegado.'}
$artifact=$manifest.artifacts | Where-Object {$_.file -eq 'Encargalo.apk'}
if(!$artifact -or (Get-FileHash $apk -Algorithm SHA256).Hash -ne $artifact.sha256){throw 'El hash de la APK no coincide.'}
# Some Android SDK tools cannot open Windows paths containing accented letters.
# Use an exact, hash-checked temporary copy; do not rebuild or alter the APK.
$temporary=Join-Path $env:LOCALAPPDATA ('Temp/opencode/encargalo-install-'+[Guid]::NewGuid().ToString('N')+'.apk')
if(Test-Path -LiteralPath $temporary){throw 'Ya existe la ruta temporal; se conserva.'}
try {
Copy-Item -LiteralPath $apk -Destination $temporary
$apk=$temporary
if((Get-FileHash $apk -Algorithm SHA256).Hash -ne $artifact.sha256){throw 'La copia temporal no coincide.'}
$identity=& $aapt dump badging $apk
if($LASTEXITCODE -ne 0 -or $identity[0] -notmatch "package: name='pe\.edu\.unp\.encargalo' versionCode='(\d+)' versionName='([^']+)'"){
 throw 'Paquete Android incorrecto.'
}
$version=$Matches[2]+'+'+$Matches[1]
if($version -ne $manifest.version){throw 'La version Android no coincide con el manifiesto.'}
$signature=& $apksigner verify --verbose --print-certs $apk
if($LASTEXITCODE -ne 0 -or !($signature -match 'certificate SHA-256 digest: 7abdfd77800cf84595f727d484b2e1e81715b93211e3db56c6b3486ac0c151a7')){
 throw 'La firma no coincide con la identidad release original.'
}
$permissions=& $aapt dump permissions $apk
if($LASTEXITCODE -ne 0){throw 'No se pudo comprobar el manifiesto Android.'}
if($permissions -match 'android.permission.(READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CONTACTS|WRITE_CONTACTS|READ_CALL_LOG|RECORD_AUDIO|READ_PHONE_STATE|MANAGE_EXTERNAL_STORAGE|QUERY_ALL_PACKAGES|SYSTEM_ALERT_WINDOW|REQUEST_INSTALL_PACKAGES|BIND_ACCESSIBILITY_SERVICE|BIND_DEVICE_ADMIN)'){
 throw 'Se detecto un permiso sensible inesperado; no se instala.'
}
$state=& $adb -s $Serial get-state
if($LASTEXITCODE -ne 0 -or $state -ne 'device'){throw 'El telefono autorizado no esta disponible.'}
# Instala exclusivamente el paquete verificado. Sin -g: NO concede permisos;
# sin cambios de ajustes, sin lectura de archivos personales ni otras apps.
$installation=& $adb -s $Serial install -r $apk
if($LASTEXITCODE -ne 0 -or !($installation -match '^Success$')){throw 'Android no confirmo la instalacion; no se fuerza ni se desactiva seguridad.'}
$launch=& $adb -s $Serial shell am start -W -n "$package/.MainActivity"
if($LASTEXITCODE -ne 0 -or !($launch -match '^Status: ok')){throw 'APK instalada, pero el inicio no se confirmo.'}
$report=@{
 checkedAt=(Get-Date).ToString('o');package=$package;version=$version;
 artifactSha256=$artifact.sha256;signatureVerified=$true;installed=$true;
 launchConfirmed=$true;permissionsAutoGranted=$false;
 cameraVerified=$false;gpsVerified=$false;pushDeliveryVerified=$false;
 serialRecorded=$false;permissions=@($permissions | Where-Object {$_ -match '^uses-permission:'})
}
$json=$report | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path (Split-Path $root -Parent) 'encargalo_documentacion/evidencias/instalacion-android.json'),$json,(New-Object Text.UTF8Encoding $false))
Write-Output $json
} finally {
 if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}
}
