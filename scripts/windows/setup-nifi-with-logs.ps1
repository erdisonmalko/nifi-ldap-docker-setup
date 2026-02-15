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

# Setup logging
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOG_DIR = Join-Path $SCRIPT_DIR "script-logs"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG_FILE = Join-Path $LOG_DIR "setup-nifi-$TIMESTAMP.log"

# Create log directory if it doesn't exist
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR | Out-Null
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    # Always write to log file
    Add-Content -Path $LOG_FILE -Value $logMessage
    
    # Write to console unless NoConsole is specified
    if (-not $NoConsole) {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Function definitions
function Test-DockerRunning {
    try {
        docker ps 2>&1 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Wait-ForContainer {
    param([string]$Container, [int]$MaxWaitSeconds = 120)
    
    Write-Log "Waiting for $Container..." -Color Yellow
    
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
    Write-Log "Waiting for NiFi to start (2-3 minutes)..." -Color Yellow
    
    $maxAttempts = 60
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        $result = docker exec nifi grep -q "Started Server on" /opt/nifi/nifi-current/logs/nifi-app.log 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        Start-Sleep -Seconds 3
        $attempt++
        if ($attempt % 10 -eq 0) {
            Write-Log "  Still waiting... ($attempt/$maxAttempts)" -Color DarkGray
        }
    }
    
    return $false
}

# Start of main script
Write-Log "`nNiFi Docker Multi-User Setup" -Color Cyan
Write-Log "===========================`n" -Color Cyan
Write-Log "Log file: $LOG_FILE`n" -Color DarkGray

# Step 0: Pre-flight checks
Write-Log "[1/8] Pre-flight checks..." -Color Cyan

if (-not (Test-DockerRunning)) {
    Write-Log "[ERROR] Docker is not running" -Color Red
    exit 1
}

if (-not (Test-Path "docker-compose.yml")) {
    Write-Log "[ERROR] docker-compose.yml not found" -Color Red
    exit 1
}

if (-not (Test-Path "ldif\init-users.ldif")) {
    Write-Log "[ERROR] ldif\init-users.ldif not found" -Color Red
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\login-identity-providers.xml")) {
    Write-Log "[ERROR] $LOCAL_CONFIG\login-identity-providers.xml not found" -Color Red
    exit 1
}

if (-not (Test-Path "$LOCAL_CONFIG\authorizers.xml")) {
    Write-Log "[ERROR] $LOCAL_CONFIG\authorizers.xml not found" -Color Red
    exit 1
}

Write-Log "  All checks passed" -Color Green

if (-not $SkipConfirmation) {
    $response = Read-Host "`nContinue with setup? (y/n)"
    if ($response -ne 'y') {
        Write-Log "Setup cancelled" -Color Yellow
        exit 0
    }
}

# Step 1: Clean slate
Write-Log "`n[2/8] Cleaning up old containers..." -Color Cyan
docker-compose down -v 2>&1 | Out-Null
Write-Log "  Done" -Color Green

# Step 2: Start services
Write-Log "`n[3/8] Starting Docker containers..." -Color Cyan
docker-compose up -d 2>&1 | Add-Content -Path $LOG_FILE
Write-Log "  Done" -Color Green

# Step 3: Wait for OpenLDAP
Write-Log "`n[4/8] Waiting for OpenLDAP..." -Color Cyan
if (-not (Wait-ForContainer -Container $LDAP_CONTAINER)) {
    Write-Log "[ERROR] OpenLDAP failed to start" -Color Red
    exit 1
}
Start-Sleep -Seconds 5
Write-Log "  Ready" -Color Green

# Step 4: Initialize LDAP users
Write-Log "`n[5/8] Creating LDAP users..." -Color Cyan
$ErrorActionPreference = "Continue"
$ldapResult = docker exec $LDAP_CONTAINER ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif 2>&1 | Out-String
Add-Content -Path $LOG_FILE -Value $ldapResult
$ldapExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($ldapExitCode -eq 0 -or $ldapResult -match "Already exists") {
    Write-Log "  Created: superAdmin, user1, user2, user3" -Color Green
} else {
    Write-Log "  Warning: Could not verify users" -Color Yellow
}

# Step 5: Wait for NiFi
Write-Log "`n[6/8] Waiting for NiFi initial startup..." -Color Cyan
if (-not (Wait-ForNiFi)) {
    Write-Log "[ERROR] NiFi failed to start" -Color Red
    exit 1
}
Write-Log "  Ready" -Color Green

# Step 6: Prepare for LDAP config
Write-Log "`n[7/8] Applying LDAP configuration..." -Color Cyan

# Delete old auth files
docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/users.xml 2>&1 | Add-Content -Path $LOG_FILE
docker exec $CONTAINER_NAME rm -f ${CONF_DIR}/authorizations.xml 2>&1 | Add-Content -Path $LOG_FILE

# Stop NiFi
docker-compose stop nifi 2>&1 | Add-Content -Path $LOG_FILE
Start-Sleep -Seconds 3

# Copy XML files
docker cp "$LOCAL_CONFIG\login-identity-providers.xml" ${CONTAINER_NAME}:${CONF_DIR}/ 2>&1 | Add-Content -Path $LOG_FILE
docker cp "$LOCAL_CONFIG\authorizers.xml" ${CONTAINER_NAME}:${CONF_DIR}/ 2>&1 | Add-Content -Path $LOG_FILE

# Update nifi.properties
docker cp ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties .\temp-nifi.properties 2>&1 | Add-Content -Path $LOG_FILE
$props = Get-Content .\temp-nifi.properties
$props = $props -replace 'nifi.security.user.login.identity.provider=.*', 'nifi.security.user.login.identity.provider=ldap-provider'
$props = $props -replace 'nifi.security.user.authorizer=.*', 'nifi.security.user.authorizer=managed-authorizer'
$props | Set-Content .\temp-nifi.properties
docker cp .\temp-nifi.properties ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties 2>&1 | Add-Content -Path $LOG_FILE
Remove-Item .\temp-nifi.properties

Write-Log "  Configuration applied" -Color Green

# Step 8: Start NiFi with LDAP
Write-Log "`n[8/8] Starting NiFi with LDAP..." -Color Cyan
docker-compose start nifi 2>&1 | Add-Content -Path $LOG_FILE

if (-not (Wait-ForNiFi)) {
    Write-Log "[ERROR] NiFi failed to start with LDAP" -Color Red
    exit 1
}
Write-Log "  Ready" -Color Green

# Success
Write-Log "`n========================================" -Color Green
Write-Log "Setup Complete!" -Color Green
Write-Log "========================================`n" -Color Green

Write-Log "NiFi:          https://localhost:8443/nifi" -Color White
Write-Log "LDAP Admin:    http://localhost:8081" -Color White
Write-Log "NiFi Registry: http://localhost:18080`n" -Color White

Write-Log "Users: superAdmin, user1, user2, user3" -Color White
Write-Log "Password: password123`n" -Color White

Write-Log "Next: Login as superAdmin and grant UI access to other users" -Color Yellow
Write-Log "Full log: $LOG_FILE`n" -Color DarkGray
