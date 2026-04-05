#!/bin/bash
# Configure NiFi Registry Client
# This script connects NiFi to NiFi Registry automatically

set -e

NIFI_URL="https://localhost:8443/nifi-api"
REGISTRY_URL_CHECK="http://localhost:18080"
REGISTRY_URL_NIFI="http://nifi-registry:18080"
REGISTRY_NAME="Local Registry"

NIFI_USERNAME="${NIFI_USERNAME:-superAdmin}"
NIFI_PASSWORD="${NIFI_PASSWORD:-password123}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================"
echo "NiFi Registry Auto-Configuration"
echo "========================================"

echo -e "\n${YELLOW}[1/5]${NC} Waiting for NiFi to be ready..."
MAX_WAIT=60
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -k -s -f "$NIFI_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}      NiFi is ready!${NC}"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}      ERROR: NiFi did not start in time${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[2/5]${NC} Checking if Registry is available..."
if curl -s -f "$REGISTRY_URL_CHECK/nifi-registry" > /dev/null 2>&1; then
    echo -e "${GREEN}      Registry is available${NC}"
else
    echo -e "${YELLOW}      Registry is not available (skipping)${NC}"
    exit 0
fi

echo -e "\n${YELLOW}[3/5]${NC} Authenticating to NiFi..."

TOKEN_RESPONSE=$(curl -k -s -X POST "$NIFI_URL/access/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$NIFI_USERNAME&password=$NIFI_PASSWORD")

if [ -z "$TOKEN_RESPONSE" ] || [ "$TOKEN_RESPONSE" == "Unable to authenticate" ]; then
    echo -e "${RED}      Authentication failed${NC}"
    exit 1
fi

TOKEN="$TOKEN_RESPONSE"
echo -e "${GREEN}      Authenticated as $NIFI_USERNAME${NC}"

echo -e "\n${YELLOW}[4/5]${NC} Checking existing Registry clients..."

EXISTING=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
    "$NIFI_URL/controller/registry-clients" | grep -o "\"name\":\"$REGISTRY_NAME\"" || true)

if [ -n "$EXISTING" ]; then
    echo -e "${GREEN}      Registry client already configured${NC}"
    exit 0
fi

echo -e "${YELLOW}      No existing Registry client found${NC}"

echo -e "\n${YELLOW}[5/5]${NC} Creating Registry client..."

PAYLOAD=$(cat <<EOF
{
  "revision": {
    "version": 0
  },
  "component": {
    "name": "$REGISTRY_NAME",
    "description": "Local NiFi Registry for version control",
    "type": "org.apache.nifi.registry.flow.NifiRegistryFlowRegistryClient",
    "properties": {
      "url": "$REGISTRY_URL_NIFI"
    }
  }
}
EOF
)

RESULT=$(curl -k -s -X POST "$NIFI_URL/controller/registry-clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if echo "$RESULT" | grep -q "\"name\":\"$REGISTRY_NAME\""; then
    echo -e "${GREEN}      Registry client created successfully!${NC}"
    echo -e "${GREEN}      Name: $REGISTRY_NAME${NC}"
    echo -e "${GREEN}      URL: $REGISTRY_URL_NIFI${NC}"
else
    echo -e "${RED}      Failed to create Registry client${NC}"
    echo -e "${YELLOW}      Error: $(echo "$RESULT" | grep -o '"message":"[^"]*"' || echo "Unknown error")${NC}"
    exit 1
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Registry Configuration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
