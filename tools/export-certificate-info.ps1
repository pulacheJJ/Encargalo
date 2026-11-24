$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$properties=Join-Path $root 'android/key.properties'
$line=Get-Content -LiteralPath $properties -Encoding UTF8 | Where-Object {$_.StartsWith('storePassword=')}
if(!$line){throw 'No se encontro la configuracion privada de firma.'}
$env:ENCARGALO_CERT_PASS=$line.Substring('storePassword='.Length)
$target=Join-Path (Split-Path $root -Parent) 'encargalo_documentacion/evidencias/certificado-firma.txt'
New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
try {
 $ErrorActionPreference='Continue'
 & "$env:JAVA_HOME/bin/keytool.exe" -list -v -alias encargalo -keystore (Join-Path $root '.secrets/encargalo-release.jks') -storepass:env ENCARGALO_CERT_PASS 2>&1 | Out-File -FilePath $target -Encoding utf8
 if($LASTEXITCODE -ne 0){throw 'No se pudo leer el certificado original.'}
 Get-Content $target | Select-String 'SHA256|SHA384|RSA|Propietario|Owner|Nombre de alias|Alias name'
} finally {Remove-Item Env:ENCARGALO_CERT_PASS -ErrorAction SilentlyContinue}
