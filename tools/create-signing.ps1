$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $root '.secrets'
$key = Join-Path $secretDir 'encargalo-release.jks'
$properties = Join-Path $root 'android/key.properties'
if ((Test-Path $key) -or (Test-Path $properties)) { throw 'Ya existe una firma/configuración. No se sobrescribe.' }
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
$random = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
$password = [Convert]::ToBase64String($random)
$env:ENCARGALO_SIGNING_PASS = $password
try {
 & "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -keystore $key -storetype JKS -alias encargalo -keyalg RSA -keysize 3072 -validity 10000 -storepass:env ENCARGALO_SIGNING_PASS -keypass:env ENCARGALO_SIGNING_PASS -dname 'CN=Encargalo, OU=Proyecto academico, O=Equipo Encargalo, L=Piura, C=PE'
 if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la firma.' }
 $normalized = $key.Replace('\','/')
 $contents = "storeFile=$normalized`nstorePassword=$password`nkeyPassword=$password`nkeyAlias=encargalo`n"
 [IO.File]::WriteAllText($properties,$contents,(New-Object Text.UTF8Encoding $false))
 $account='*'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 & icacls $secretDir /inheritance:r /grant:r "$($account):(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
 & icacls $key /inheritance:r /grant:r "$($account):F" 'SYSTEM:F' | Out-Null
 & icacls $properties /inheritance:r /grant:r "$($account):F" 'SYSTEM:F' | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Debe revisarse la proteccion de la firma antes de distribuir.'}
 Write-Output 'Firma nueva creada. Respaldar .secrets/ y android/key.properties fuera de Git, con acceso restringido.'
} finally { Remove-Item Env:ENCARGALO_SIGNING_PASS -ErrorAction SilentlyContinue }
