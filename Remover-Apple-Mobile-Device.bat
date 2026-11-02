@echo off
title Remover Apple Mobile Device e programas Apple
color 0B

:: --- Pede permissao de administrador automaticamente ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo   REMOVER APPLE MOBILE DEVICE E PROGRAMAS APPLE
echo ============================================================
echo.
echo Este script vai remover do Windows:
echo   iTunes, Apple Devices, Apple Music, iCloud,
echo   Apple Software Update, Apple Mobile Device Support,
echo   Bonjour, Apple Application Support, o driver USB da Apple
echo   e as chaves da Apple no registro do Windows.
echo.
echo Antes de mexer no registro, o script cria um ponto de restauracao e
echo salva uma copia (.reg) na pasta Backup-Registro-Apple da Area de Trabalho.
echo.
echo Seus backups do iPhone e sua biblioteca de musicas NAO serao apagados.
echo Desconecte o iPhone do cabo USB antes de continuar.
echo.
choice /C SN /M "Deseja continuar"
if errorlevel 2 exit /b

powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=Get-Content -Raw -LiteralPath '%~f0'; $i=$c.IndexOf('#PS1'+'START'); Invoke-Expression $c.Substring($i)"

echo.
echo ============================================================
echo   Concluido. REINICIE o computador para finalizar a remocao.
echo ============================================================
pause
exit /b

#PS1START
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "`n[Preparando] Criando ponto de restauracao..." -ForegroundColor Cyan
Enable-ComputerRestore -Drive "$env:SystemDrive\"
Checkpoint-Computer -Description 'Antes de remover Apple' -RestorePointType MODIFY_SETTINGS

Write-Host "`n[1/7] Encerrando processos e servicos da Apple..." -ForegroundColor Cyan
'iTunes','iTunesHelper','iCloudServices','iCloudDrive','iCloudPhotos','AppleMobileDeviceService','AppleMobileDeviceHelper','iPodService','APSDaemon','distnoted','SyncServicesAgent' |
    ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force }
'Apple Mobile Device Service','Bonjour Service' |
    ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }

Write-Host "[2/7] Removendo apps da Microsoft Store (iTunes, Apple Devices, Apple Music, iCloud)..." -ForegroundColor Cyan
'AppleInc.iTunes','AppleInc.AppleDevices','AppleInc.AppleMusicWin','AppleInc.iCloud' | ForEach-Object {
    $pk = Get-AppxPackage -AllUsers -Name $_
    if ($pk) { Write-Host "   - $_"; $pk | Remove-AppxPackage -AllUsers }
}

Write-Host "[3/7] Desinstalando programas classicos na ordem correta..." -ForegroundColor Cyan
$chaves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$ordem  = 'iTunes','iCloud','Apple Software Update','Apple Mobile Device Support','Bonjour',
          'Apple Application Support (64','Apple Application Support (32','Apple Application Support'
foreach ($nome in $ordem) {
    $itens = Get-ItemProperty $chaves | Where-Object { $_.DisplayName -like "$nome*" }
    foreach ($app in $itens) {
        $un = "$($app.UninstallString)"
        if ($un -match '\{[0-9A-Fa-f\-]{36}\}') {
            Write-Host "   - Removendo: $($app.DisplayName)"
            Start-Process msiexec.exe -ArgumentList "/x $($matches[0]) /qn /norestart" -Wait
        } elseif ($un) {
            Write-Host "   ! $($app.DisplayName) nao usa MSI. Desinstale manualmente em Configuracoes > Aplicativos." -ForegroundColor Yellow
        }
    }
}

Write-Host "[4/7] Removendo driver USB da Apple..." -ForegroundColor Cyan
Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -like 'Apple*' } | ForEach-Object {
    Write-Host "   - $($_.Driver)"
    pnputil.exe /delete-driver $_.Driver /uninstall /force | Out-Null
}

Write-Host "[5/7] Removendo servico residual..." -ForegroundColor Cyan
if (Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue) {
    sc.exe delete 'Apple Mobile Device Service' | Out-Null
}

Write-Host "[6/7] Limpando pastas que sobraram..." -ForegroundColor Cyan
$pastas = "$env:ProgramFiles\Common Files\Apple",
          "${env:ProgramFiles(x86)}\Common Files\Apple",
          "$env:ProgramFiles\iTunes",
          "$env:ProgramFiles\iPod",
          "$env:ProgramFiles\iCloud",
          "$env:ProgramFiles\Bonjour",
          "${env:ProgramFiles(x86)}\Bonjour"
foreach ($p in $pastas) {
    if (Test-Path $p) { Write-Host "   - $p"; Remove-Item -Path $p -Recurse -Force }
}

Write-Host "[7/7] Limpando o registro do Windows..." -ForegroundColor Cyan
$bk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Backup-Registro-Apple'
New-Item -ItemType Directory -Path $bk -Force | Out-Null
function Remover-Chave($chave, $arq) {
    if (Test-Path -LiteralPath ("Registry::" + $chave)) {
        Write-Host "   - $chave"
        reg.exe export "$chave" "$bk\$arq.reg" /y | Out-Null
        Remove-Item -LiteralPath ("Registry::" + $chave) -Recurse -Force
    }
}
# Chaves de configuracao da Apple e dos servicos
$regs = 'HKEY_LOCAL_MACHINE\SOFTWARE\Apple Inc.',
        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Apple Inc.',
        'HKEY_LOCAL_MACHINE\SOFTWARE\Apple Computer, Inc.',
        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Apple Computer, Inc.',
        'HKEY_CURRENT_USER\Software\Apple Inc.',
        'HKEY_CURRENT_USER\Software\Apple Computer, Inc.',
        'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Apple Mobile Device Service',
        'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Bonjour Service'
$i = 0
foreach ($r in $regs) { $i++; Remover-Chave $r ("chave_$i") }
# Entradas orfas na lista de programas instalados (somente Apple e somente os nomes da lista)
$nomes = 'iTunes','iCloud','Apple Software Update','Apple Mobile Device Support','Bonjour','Apple Application Support'
$bases = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
         'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
foreach ($b in $bases) {
    Get-ChildItem $b | ForEach-Object {
        $pr = Get-ItemProperty $_.PSPath
        if ($pr.DisplayName -and $pr.Publisher -like 'Apple*') {
            foreach ($n in $nomes) {
                if ($pr.DisplayName -like "$n*") { Remover-Chave $_.Name ("uninstall_" + $_.PSChildName); break }
            }
        }
    }
}
Write-Host "   Copia de seguranca do registro salva em: $bk" -ForegroundColor Green
