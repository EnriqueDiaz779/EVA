$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectDir "env\Scripts\python.exe"
$Manage = Join-Path $ProjectDir "manage.py"
$EnvFile = Join-Path $ProjectDir ".env"

if (-not (Test-Path $Python)) {
    Write-Error "No se encontro el entorno virtual en: $Python"
    Write-Host "Crea o reinstala dependencias con:"
    Write-Host "  cd $ProjectDir"
    Write-Host "  python -m venv env"
    Write-Host "  .\env\Scripts\python.exe -m pip install -r requirements.txt"
    exit 1
}

if (Test-Path $EnvFile) {
    $HasDatabaseUrl = Select-String -Path $EnvFile -Pattern "^DATABASE_URL=.+$" -Quiet
    $HasRailwayDatabaseUrl = Select-String -Path $EnvFile -Pattern "^RAILWAY_DATABASE_URL=.+$" -Quiet
    $HasPassword = Select-String -Path $EnvFile -Pattern "^DB_PASSWORD=.+$" -Quiet

    if (-not $HasDatabaseUrl -and -not $HasRailwayDatabaseUrl -and -not $HasPassword) {
        Write-Error "Falta DB_PASSWORD en $EnvFile. Django esta intentando entrar a MySQL sin contrasena."
        Write-Host "Agrega tus datos de MySQL al archivo .env, por ejemplo:"
        Write-Host "  DB_NAME=eva_db"
        Write-Host "  DB_USER=eva_user"
        Write-Host "  DB_PASSWORD=tu_contrasena_de_mysql"
        Write-Host "  DB_HOST=127.0.0.1"
        Write-Host "  DB_PORT=3306"
        Write-Host "  DB_SSL_REQUIRED=False"
        exit 1
    }
}

& $Python $Manage runserver 0.0.0.0:8000
