# Deploy del backend CarMain al VPS Oracle (linux/arm64) desde Windows.
#
# Uso:
#   .\deploy.ps1                        # con los defaults de abajo
#   .\deploy.ps1 -VpsHost mihost.duckdns.org
#
# Requisitos en el VPS (una sola vez, ver plan deploy-vps):
#   - usuario "carmain" y /opt/carmain con su .env (chmod 600)
#   - Caddy con reverse_proxy localhost:8080
#
# El .env NO se deploya: se gestiona a mano en el VPS.
param(
  [string]$VpsHost = "CAMBIA-ME.duckdns.org",
  [string]$VpsUser = "ubuntu",
  [string]$KeyFile = "$env:USERPROFILE\.ssh\carmain_vps",
  # Go no está en el PATH de este PC — ruta del toolchain local.
  [string]$GoExe = "C:\Users\David\go-toolchain\go\bin\go.exe"
)
$ErrorActionPreference = "Stop"
if ($VpsHost -like "CAMBIA-ME*") { throw "Edita -VpsHost (o el default) con tu subdominio DuckDNS." }

Push-Location $PSScriptRoot
try {
  # 1. Compilar web-mecanico y actualizar dist embebido
  Write-Host "Compilando SPA web-mecanico..." -ForegroundColor Cyan
  Push-Location "$PSScriptRoot\..\web-mecanico"
  npm run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build fallo en web-mecanico" }
  Pop-Location

  if (Test-Path "$PSScriptRoot\webmecanico\dist") {
    Remove-Item -Recurse -Force "$PSScriptRoot\webmecanico\dist"
  }
  Copy-Item -Recurse "$PSScriptRoot\..\web-mecanico\dist" "$PSScriptRoot\webmecanico\dist"
  Write-Host "web-mecanico embebido actualizado" -ForegroundColor Green

  # 2. Cross-compile para ARM64 sin CGO.
  $env:GOOS = "linux"; $env:GOARCH = "arm64"; $env:CGO_ENABLED = "0"
  & $GoExe build -trimpath -ldflags "-s -w" -o build/carmain-server .
  if ($LASTEXITCODE -ne 0) { throw "go build fallo" }
  Write-Host "binario arm64 compilado" -ForegroundColor Green

  scp -i $KeyFile build/carmain-server "${VpsUser}@${VpsHost}:/tmp/carmain-server"
  scp -i $KeyFile carmain.service "${VpsUser}@${VpsHost}:/tmp/carmain.service"

  ssh -i $KeyFile "${VpsUser}@${VpsHost}" `
    "sudo install -m 755 -o carmain -g carmain /tmp/carmain-server /opt/carmain/carmain-server && " + `
    "sudo install -m 644 /tmp/carmain.service /etc/systemd/system/carmain.service && " + `
    "sudo systemctl daemon-reload && sudo systemctl restart carmain && " + `
    "sleep 2 && systemctl is-active carmain && file /opt/carmain/carmain-server"

  Write-Host "deploy OK — servicio activo" -ForegroundColor Green
} finally {
  Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
  Pop-Location
}
