#!/bin/bash

set -e

# =========================
# Configuration
# =========================
CONTAINER_NAME="nifi"
LDAP_CONTAINER="nifi-openldap"
CONF_DIR="/opt/nifi/nifi-current/conf"
LOCAL_CONFIG="./nifi-config-backup"

SKIP_CONFIRMATION=false

if [[ "$1" == "--skip-confirmation" ]]; then
  SKIP_CONFIRMATION=true
fi

# =========================
# Functions
# =========================

test_docker_running() {
  docker ps > /dev/null 2>&1
}

wait_for_container() {
  local container=$1
  local max_wait=${2:-120}
  local elapsed=0

  echo "Waiting for $container..."

  while [[ $elapsed -lt $max_wait ]]; do
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "notfound")
    if [[ "$status" == "running" ]]; then
      sleep 2
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

wait_for_nifi() {
  echo "Waiting for NiFi to start (2-3 minutes)..."

  local max_attempts=60
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    if docker exec "$CONTAINER_NAME" grep -q "Started Server on" /opt/nifi/nifi-current/logs/nifi-app.log 2>/dev/null; then
      echo "[OK] NiFi is ready!"
      return 0
    fi

    sleep 3
    attempt=$((attempt + 1))

    if (( attempt % 10 == 0 )); then
      echo "  Still waiting... ($attempt/$max_attempts)"
    fi
  done

  return 1
}

# =========================
# Start Script
# =========================

echo ""
echo "========================================================"
echo "  NiFi Docker Multi-User Setup - Automated Installer"
echo "========================================================"
echo ""

# Step 0: Pre-flight checks
echo "Step 0: Pre-flight checks"
echo "-------------------------"
echo ""

if ! test_docker_running; then
  echo "[ERROR] Docker is not running."
  exit 1
fi

if [[ ! -f "docker-compose.yml" ]]; then
  echo "[ERROR] docker-compose.yml not found."
  exit 1
fi

if [[ ! -f "ldif/init-users.ldif" ]]; then
  echo "[ERROR] ldif/init-users.ldif not found."
  exit 1
fi

if [[ ! -f "$LOCAL_CONFIG/login-identity-providers.xml" ]]; then
  echo "[ERROR] Missing login-identity-providers.xml"
  exit 1
fi

if [[ ! -f "$LOCAL_CONFIG/authorizers.xml" ]]; then
  echo "[ERROR] Missing authorizers.xml"
  exit 1
fi

echo "[OK] Docker is running"
echo "[OK] All required config files found"
echo ""

if [[ "$SKIP_CONFIRMATION" = false ]]; then
  read -p "This will set up NiFi with LDAP authentication. Continue? (y/n): " response
  if [[ "$response" != "y" ]]; then
    echo "[CANCELLED]"
    exit 0
  fi
fi

# Step 1: Cleanup
echo ""
echo "Step 1: Removing old containers and volumes"
echo "--------------------------------------------"
echo ""

docker-compose down -v > /dev/null 2>&1 || true
echo "[OK] Cleaned up"

# Step 2: Start services
echo ""
echo "Step 2: Starting Docker containers"
echo "-----------------------------------"
echo ""

docker-compose up -d > /dev/null 2>&1
echo "[OK] Containers starting"

# Step 3: Wait for OpenLDAP
echo ""
echo "Step 3: Waiting for OpenLDAP"
echo "----------------------------"
echo ""

if ! wait_for_container "$LDAP_CONTAINER"; then
  echo "[ERROR] OpenLDAP failed to start"
  exit 1
fi

sleep 5
echo "[OK] OpenLDAP ready"

# Step 4: Initialize LDAP users
echo ""
echo "Step 4: Creating LDAP users"
echo "----------------------------"
echo ""

set +e
ldap_result=$(docker exec "$LDAP_CONTAINER" ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif 2>&1)
ldap_exit=$?
set -e

if [[ $ldap_exit -eq 0 || "$ldap_result" == *"Already exists"* ]]; then
  echo "[OK] LDAP users ready"
else
  echo "[WARN] Could not verify LDAP users"
fi

# Step 5: Wait for NiFi
echo ""
echo "Step 5: Waiting for NiFi initial startup"
echo "-----------------------------------------"
echo ""

if ! wait_for_nifi; then
  echo "[ERROR] NiFi failed to start"
  exit 1
fi

# Step 6: Prepare LDAP config
echo ""
echo "Step 6: Preparing LDAP configuration"
echo "-------------------------------------"
echo ""

docker exec "$CONTAINER_NAME" rm -f ${CONF_DIR}/users.xml || true
docker exec "$CONTAINER_NAME" rm -f ${CONF_DIR}/authorizations.xml || true
echo "[OK] Removed old auth files"

docker-compose stop nifi > /dev/null 2>&1
sleep 3
echo "[OK] NiFi stopped"

# Step 7: Apply config
echo ""
echo "Step 7: Applying LDAP configuration"
echo "------------------------------------"
echo ""

docker cp "$LOCAL_CONFIG/login-identity-providers.xml" ${CONTAINER_NAME}:${CONF_DIR}/
docker cp "$LOCAL_CONFIG/authorizers.xml" ${CONTAINER_NAME}:${CONF_DIR}/

docker cp ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties ./temp-nifi.properties

sed -i 's|nifi.security.user.login.identity.provider=.*|nifi.security.user.login.identity.provider=ldap-provider|' temp-nifi.properties
sed -i 's|nifi.security.user.authorizer=.*|nifi.security.user.authorizer=managed-authorizer|' temp-nifi.properties

docker cp ./temp-nifi.properties ${CONTAINER_NAME}:${CONF_DIR}/nifi.properties
rm -f temp-nifi.properties

echo "[OK] Configuration applied"

# Step 8: Restart NiFi
echo ""
echo "Step 8: Starting NiFi with LDAP"
echo "--------------------------------"
echo ""

docker-compose start nifi > /dev/null 2>&1

if ! wait_for_nifi; then
  echo "[ERROR] NiFi failed to start with LDAP"
  exit 1
fi

# Step 9: Registry (optional)
echo ""
echo "Step 9: Configuring NiFi Registry connection (optional)"
echo "-------------------------------------------------------"
echo ""

if [[ -f "./scripts/linux/configure-registry.sh" ]]; then
  echo "Running Registry configuration..."
  set +e
  sed -i 's/\r$//' ./scripts/linux/configure-registry.sh
  bash ./scripts/linux/configure-registry.sh > /dev/null 2>&1
  result=$?
  set -e

  if [[ $result -eq 0 ]]; then
    echo "[OK] Registry connected"
  else
    echo "[SKIP] Registry setup skipped"
  fi
else
  echo "[SKIP] Registry script not found"
fi

# Final Output
echo ""
echo "========================================================"
echo "Setup Complete"
echo "========================================================"
echo ""

echo "NiFi:          https://localhost:8443/nifi"
echo "LDAP Admin:    http://localhost:8081"
echo "NiFi Registry: http://localhost:18080/nifi-registry"
echo ""
echo "Users: superAdmin, user1, user2, user3"
echo "Password: password123"