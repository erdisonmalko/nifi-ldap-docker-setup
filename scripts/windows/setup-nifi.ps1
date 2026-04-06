# NiFi Docker - Automated LDAP Setup
# This script applies pre-configured LDAP settings to a fresh NiFi installation

param(
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

# Configuration
$CONTAINER_NAME = "nifi"
$LDAP_CONTAINER = "nifi-openldap"
$CONF_DIR = "/opt/nifi/nifi-current/conf"
$LOCAL_CONFIG = ".\nifi-config-backup"

# Function definitions
function Test-DockerRunning {
    try {
        $null = docker ps 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Wait-ForContainer {
    param([string]$Container, [int]$MaxWaitSeconds = 120)
    
    Write-Host "Waiting for $Container..." -ForegroundColor Yellow
    
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        $status = docker inspect --format='{{.State.Status}}' $Container 2>$null
        if ($status -eq "running") {
            Start-Sleep -Seconds 2
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    return $false
}

function Wait-ForNiFi {
    Write-Host "Waiting for NiFi to start (2-3 minutes)..." -ForegroundColor Yellow
    
    $maxAttempts = 60
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        $null = docker exec nifi grep -q "Started Server on" /opt/nifi/nifi-current/logs/nifi-app.log 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] NiFi is ready!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 3
        $attempt++
        if ($attempt % 10 -eq 0) {
            Write-Host "  Still waiting... ($attempt/$maxAttempts)" -ForegroundColor DarkGray
        }
    }
    return $false
}

# Start of main script
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  NiFi Docker Multi-User Setup - Automated Installer  " -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# Step 0: Pre-flight checks
Write-Host "Step 0: Pre-flight checks" -ForegroundColor Cyan
Write-Host "-------------------------`n" -ForegroundColor DarkGray

if (-not (Test-DockerRunning)) {
    Write-Host "[ERROR] Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "docker-compose.yml")) {
    Write-Host "[ERROR] docker-compose.yml not found." -ForegroundColor Red
    Write-Host "Please run this script from the nifi-docker root directory." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path "ldif\init-users.ldif")) {
    Write-Host "[ERROR] ldif\init-users.ldif not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\login-identity-providers.xml")) {
    Write-Host "[ERROR] $LOCAL_CONFIG\login-identity-providers.xml not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\authorizers.xml")) {
    Write-Host "[ERROR] $LOCAL_CONFIG\authorizers.xml not found." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Docker is running" -ForegroundColor Green
Write-Host "[OK] All required config files found`n" -ForegroundColor Green

if (-not $SkipConfirmation) {
    Write-Host "This will set up NiFi with LDAP authentication." -ForegroundColor White
    $response = Read-Host "Continue? (y/n)"
    if ($response -ne 'y') {
        Write-Host "[CANCELLED] Setup cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Step 1: Removing old containers and volumes
Write-Host "`nStep 1: Removing old containers and volumes" -ForegroundColor Cyan
Write-Host "--------------------------------------------`n" -ForegroundColor DarkGray

$ErrorActionPreference = "SilentlyContinue"
docker-compose down -v 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Write-Host "[OK] Cleaned up`n" -ForegroundColor Green

# Step 2: Start services
Write-Host "Step 2: Starting Docker containers" -ForegroundColor Cyan
Write-Host "-----------------------------------`n" -ForegroundColor DarkGray

$ErrorActionPreference = "SilentlyContinue"
docker-compose up -d 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Write-Host "[OK] Containers starting`n" -ForegroundColor Green

# Step 3: Wait for OpenLDAP
Write-Host "Step 3: Waiting for OpenLDAP" -ForegroundColor Cyan
Write-Host "----------------------------`n" -ForegroundColor DarkGray

if (-not (Wait-ForContainer -Container $LDAP_CONTAINER)) {
    Write-Host "[ERROR] OpenLDAP failed to start" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs openldap" -ForegroundColor Yellow
    exit 1
}

Start-Sleep -Seconds 5
Write-Host "[OK] OpenLDAP ready`n" -ForegroundColor Green

# Step 4: Initialize LDAP users
Write-Host "Step 4: Creating LDAP users" -ForegroundColor Cyan
Write-Host "----------------------------`n" -ForegroundColor DarkGray

$ErrorActionPreference = "Continue"
$ldapResult = docker exec $LDAP_CONTAINER ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif 2>&1
$ldapExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($ldapExitCode -eq 0 -or ($ldapResult -match "Already exists")) {
    Write-Host "[OK] LDAP users ready:" -ForegroundColor Green
    Write-Host "  superAdmin, user1, user2, user3 (password: password123)`n" -ForegroundColor White
} else {
    Write-Host "[WARN] Could not verify LDAP users" -ForegroundColor Yellow
    Write-Host "Continuing anyway...`n" -ForegroundColor Yellow
}

# Step 5: Wait for NiFi initial startup
Write-Host "Step 5: Waiting for NiFi initial startup" -ForegroundColor Cyan
Write-Host "-----------------------------------------`n" -ForegroundColor DarkGray

if (-not (Wait-ForNiFi)) {
    Write-Host "[ERROR] NiFi failed to start in time" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs nifi" -ForegroundColor Yellow
    Write-Host "The container may still be starting. Wait a minute and check:" -ForegroundColor Yellow
    Write-Host "  docker logs nifi | Select-String 'Started Server'" -ForegroundColor Cyan
    exit 1
}

# Step 6: Prepare for LDAP configuration
Write-Host "`nStep 6: Preparing LDAP configuration" -ForegroundColor Cyan
Write-Host "-------------------------------------`n" -ForegroundColor DarkGray

# Delete old auth files while container is running
$null = docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/users.xml 2>&1
$null = docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/authorizations.xml 2>&1
Write-Host "[OK] Removed old auth files" -ForegroundColor Green

# Stop NiFi
$ErrorActionPreference = "SilentlyContinue"
docker-compose stop nifi 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Start-Sleep -Seconds 3
Write-Host "[OK] NiFi stopped`n" -ForegroundColor Green

# Step 7: Apply LDAP configuration
Write-Host "Step 7: Applying LDAP configuration" -ForegroundColor Cyan
Write-Host "------------------------------------`n" -ForegroundColor DarkGray

# Copy XML files
$null = docker cp "$LOCAL_CONFIG\login-identity-providers.xml" ${CONTAINER_NAME}:${CONF_DIR}/ 2>&1
Write-Host "[OK] Copied login-identity-providers.xml" -ForegroundColor Green

$null = docker cp "$LOCAL_CONFIG\authorizers.xml" ${CONTAINER_NAME}:${CONF_DIR}/ 2>&1
Write-Host "[OK] Copied authorizers.xml" -ForegroundColor Green

# Update nifi.properties (only the 2 lines we need)
$null = docker cp ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties .\temp-nifi.properties 2>&1
$props = Get-Content .\temp-nifi.properties
$props = $props -replace 'nifi.security.user.login.identity.provider=.*', 'nifi.security.user.login.identity.provider=ldap-provider'
$props = $props -replace 'nifi.security.user.authorizer=.*', 'nifi.security.user.authorizer=managed-authorizer'
$props | Set-Content .\temp-nifi.properties
$null = docker cp .\temp-nifi.properties ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties 2>&1
Remove-Item .\temp-nifi.properties -ErrorAction SilentlyContinue
Write-Host "[OK] Updated nifi.properties`n" -ForegroundColor Green

# Step 8: Start NiFi with LDAP
Write-Host "Step 8: Starting NiFi with LDAP" -ForegroundColor Cyan
Write-Host "--------------------------------`n" -ForegroundColor DarkGray

$ErrorActionPreference = "SilentlyContinue"
docker-compose start nifi 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

if (-not (Wait-ForNiFi)) {
    Write-Host "[ERROR] NiFi failed to start with LDAP config" -ForegroundColor Red
    Write-Host "Check logs for errors: docker-compose logs nifi | Select-String 'ERROR'" -ForegroundColor Yellow
    exit 1
}

# Success!
Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "              Setup Complete!                           " -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Green

# Step 9: Configure Registry (optional)
Write-Host "Step 9: Configuring NiFi Registry connection (optional)" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------`n" -ForegroundColor DarkGray

# THIS WILL PROBABLY FAIL ON WINDOWS DUE TO BASH SCRIPT, 
# BUT WE CAN STILL TRY TO RUN IT IF WSL IS AVAILABLE. OTHERWISE, 
# USER CAN CONFIGURE REGISTRY MANUALLY USING THE UI.

if (Test-Path ".\scripts\linux\configure-registry.sh") {
    Write-Host "Running Registry configuration..." -ForegroundColor Yellow
    $ErrorActionPreference = "Continue"
    bash ./scripts/linux/configure-registry.sh 2>&1 | Out-Null
    $registryResult = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    
    if ($registryResult -eq 0) {
        Write-Host "[OK] Registry connected to NiFi" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Registry configuration skipped (add manually if needed)`n" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Registry script not found (add connection manually)`n" -ForegroundColor Yellow
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "              All Done!                                 " -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Green

Write-Host "NiFi:          " -NoNewline -ForegroundColor White
Write-Host "https://localhost:8443/nifi" -ForegroundColor Cyan

Write-Host "LDAP Admin:    " -NoNewline -ForegroundColor White
Write-Host "http://localhost:8081" -ForegroundColor Cyan

Write-Host "NiFi Registry: " -NoNewline -ForegroundColor White
Write-Host "http://localhost:18080/nifi-registry`n" -ForegroundColor Cyan

Write-Host "Users: " -NoNewline -ForegroundColor White
Write-Host "superAdmin, user1, user2, user3" -ForegroundColor Yellow

Write-Host "Password: " -NoNewline -ForegroundColor White
Write-Host "password123`n" -ForegroundColor Yellow

Write-Host "Next Steps:" -ForegroundColor White
Write-Host "-----------" -ForegroundColor DarkGray
Write-Host "  1. Login as superAdmin" -ForegroundColor White
Write-Host "  2. Grant UI access to other users (Policies menu)" -ForegroundColor White
Write-Host "  3. Create team Process Groups" -ForegroundColor White
Write-Host "  4. Set access policies per team`n" -ForegroundColor White

Write-Host "Commands:" -ForegroundColor White
Write-Host "---------" -ForegroundColor DarkGray
Write-Host "  Logs:    docker-compose logs -f nifi" -ForegroundColor White
Write-Host "  Stop:    docker-compose down" -ForegroundColor White
Write-Host "  Restart: docker-compose restart nifi`n" -ForegroundColor White
