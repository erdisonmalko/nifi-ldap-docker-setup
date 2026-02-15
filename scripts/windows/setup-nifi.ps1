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
        docker ps | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Wait-ForContainer {
    param([string]$Container, [int]$MaxWaitSeconds = 120)
    
    Write-Host "Waiting for $Container to be ready..." -ForegroundColor Yellow
    
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        $status = docker inspect --format='{{.State.Status}}' $Container 2>$null
        if ($status -eq "running") {
            Start-Sleep -Seconds 2
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""
    return $false
}

function Wait-ForNiFi {
    Write-Host "Waiting for NiFi to start (this takes 2-3 minutes)..." -ForegroundColor Yellow
    
    $maxAttempts = 60
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        $result = docker exec nifi grep -q "Started Server on" /opt/nifi/nifi-current/logs/nifi-app.log 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n[OK] NiFi is ready!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 3
        $attempt++
        Write-Host "." -NoNewline
    }
    
    Write-Host ""
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
    Write-Host "[ERROR] docker-compose.yml not found. Please run from the nifi-docker directory." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "ldif\init-users.ldif")) {
    Write-Host "[ERROR] ldif\init-users.ldif not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\login-identity-providers.xml")) {
    Write-Host "[ERROR] $LOCAL_CONFIG\login-identity-providers.xml not found." -ForegroundColor Red
    Write-Host "This file should be in your git repository." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\authorizers.xml")) {
    Write-Host "[ERROR] $LOCAL_CONFIG\authorizers.xml not found." -ForegroundColor Red
    Write-Host "This file should be in your git repository." -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Docker is running" -ForegroundColor Green
Write-Host "[OK] All required config files found`n" -ForegroundColor Green

if (-not $SkipConfirmation) {
    Write-Host "This will set up NiFi with LDAP authentication using pre-configured files." -ForegroundColor White
    $response = Read-Host "Continue? (y/n)"
    if ($response -ne 'y') {
        Write-Host "[CANCELLED] Setup cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Step 1: Clean slate
Write-Host "`nStep 1: Clean slate - Removing old containers and volumes" -ForegroundColor Cyan
Write-Host "---------------------------------------------------------`n" -ForegroundColor DarkGray

docker-compose down -v 2>&1 | Out-Null
Write-Host "[OK] Cleaned up old containers and volumes`n" -ForegroundColor Green

# Step 2: Start services
Write-Host "Step 2: Starting Docker containers" -ForegroundColor Cyan
Write-Host "-----------------------------------`n" -ForegroundColor DarkGray

docker-compose up -d
Write-Host "[OK] Containers starting...`n" -ForegroundColor Green

# Step 3: Wait for OpenLDAP
Write-Host "Step 3: Waiting for OpenLDAP" -ForegroundColor Cyan
Write-Host "----------------------------`n" -ForegroundColor DarkGray

if (-not (Wait-ForContainer -Container $LDAP_CONTAINER)) {
    Write-Host "[ERROR] OpenLDAP failed to start" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs openldap" -ForegroundColor Yellow
    exit 1
}

Start-Sleep -Seconds 5
Write-Host "`n[OK] OpenLDAP is ready`n" -ForegroundColor Green

# Step 4: Initialize LDAP users
Write-Host "Step 4: Creating LDAP users" -ForegroundColor Cyan
Write-Host "----------------------------`n" -ForegroundColor DarkGray

$ErrorActionPreference = "Continue"
$ldapResult = docker exec $LDAP_CONTAINER ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif 2>&1 | Out-String
$ldapExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($ldapExitCode -eq 0 -or $ldapResult -match "Already exists") {
    Write-Host "[OK] LDAP users ready:" -ForegroundColor Green
    Write-Host "  - superAdmin (password: password123)" -ForegroundColor White
    Write-Host "  - user1 (password: password123)" -ForegroundColor White
    Write-Host "  - user2 (password: password123)" -ForegroundColor White
    Write-Host "  - user3 (password: password123)`n" -ForegroundColor White
} else {
    Write-Host "[WARN] Could not verify LDAP users" -ForegroundColor Yellow
    Write-Host "Continuing with setup...`n" -ForegroundColor Yellow
}

# Step 5: Wait for NiFi (initial start to generate keystore)
Write-Host "Step 5: Waiting for NiFi initial startup" -ForegroundColor Cyan
Write-Host "-----------------------------------------`n" -ForegroundColor DarkGray

if (-not (Wait-ForNiFi)) {
    Write-Host "[ERROR] NiFi failed to start" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs nifi" -ForegroundColor Yellow
    exit 1
}

# Step 6: Stop NiFi and prepare for LDAP config
Write-Host "`nStep 6: Preparing NiFi for LDAP configuration" -ForegroundColor Cyan
Write-Host "----------------------------------------------`n" -ForegroundColor DarkGray

# Delete old single-user auth files BEFORE stopping
docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/users.xml 2>&1 | Out-Null
docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/authorizations.xml 2>&1 | Out-Null
Write-Host "[OK] Removed old authorization files" -ForegroundColor Green

# Now stop NiFi
docker-compose stop nifi
Start-Sleep -Seconds 3
Write-Host "[OK] NiFi stopped`n" -ForegroundColor Green

# Step 7: Apply pre-configured files
Write-Host "Step 7: Applying LDAP configuration" -ForegroundColor Cyan
Write-Host "------------------------------------`n" -ForegroundColor DarkGray

# Copy the 2 XML files
docker cp "$LOCAL_CONFIG\login-identity-providers.xml" ${CONTAINER_NAME}:${CONF_DIR}/
Write-Host "[OK] Copied login-identity-providers.xml" -ForegroundColor Green

docker cp "$LOCAL_CONFIG\authorizers.xml" ${CONTAINER_NAME}:${CONF_DIR}/
Write-Host "[OK] Copied authorizers.xml" -ForegroundColor Green

# Update nifi.properties - only change the 2 lines we need, keep the rest
docker cp ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties .\temp-nifi.properties
$props = Get-Content .\temp-nifi.properties
$props = $props -replace 'nifi.security.user.login.identity.provider=.*', 'nifi.security.user.login.identity.provider=ldap-provider'
$props = $props -replace 'nifi.security.user.authorizer=.*', 'nifi.security.user.authorizer=managed-authorizer'
$props | Set-Content .\temp-nifi.properties
docker cp .\temp-nifi.properties ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties
Remove-Item .\temp-nifi.properties
Write-Host "[OK] Updated nifi.properties (LDAP settings)`n" -ForegroundColor Green

# Step 8: Start NiFi with LDAP
Write-Host "Step 8: Starting NiFi with LDAP authentication" -ForegroundColor Cyan
Write-Host "-----------------------------------------------`n" -ForegroundColor DarkGray

docker-compose start nifi

if (-not (Wait-ForNiFi)) {
    Write-Host "[ERROR] NiFi failed to start with LDAP config" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs nifi" -ForegroundColor Yellow
    exit 1
}

# Step 9: Success!
Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "              Setup Complete!                           " -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Green

Write-Host "NiFi is ready at: " -NoNewline -ForegroundColor White
Write-Host "https://localhost:8443/nifi`n" -ForegroundColor Cyan

Write-Host "Available Users:" -ForegroundColor White
Write-Host "----------------" -ForegroundColor DarkGray
Write-Host "  Username: superAdmin  Password: password123" -ForegroundColor White
Write-Host "  Username: user1       Password: password123" -ForegroundColor White
Write-Host "  Username: user2       Password: password123" -ForegroundColor White
Write-Host "  Username: user3       Password: password123`n" -ForegroundColor White

Write-Host "Management Tools:" -ForegroundColor White
Write-Host "-----------------" -ForegroundColor DarkGray
Write-Host "  LDAP Admin:     http://localhost:8081" -ForegroundColor White
Write-Host "  NiFi Registry:  http://localhost:18080`n" -ForegroundColor White

Write-Host "Next Steps:" -ForegroundColor White
Write-Host "-----------" -ForegroundColor DarkGray
Write-Host "  1. Login as superAdmin" -ForegroundColor White
Write-Host "  2. Grant UI access to user1, user2, user3 via Policies menu" -ForegroundColor White
Write-Host "  3. Create Process Groups for teams" -ForegroundColor White
Write-Host "  4. Set access policies for each team`n" -ForegroundColor White

Write-Host "Useful Commands:" -ForegroundColor White
Write-Host "----------------" -ForegroundColor DarkGray
Write-Host "  View logs:      docker-compose logs -f nifi" -ForegroundColor White
Write-Host "  Stop all:       docker-compose down" -ForegroundColor White
Write-Host "  Restart NiFi:   docker-compose restart nifi`n" -ForegroundColor White

Write-Host "Your multi-user NiFi environment is ready to use!`n" -ForegroundColor Green
