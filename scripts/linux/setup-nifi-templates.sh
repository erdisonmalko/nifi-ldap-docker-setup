#!/bin/bash
# NiFi Template Setup - Controller Services and Oracle Flow
# This script automatically creates Controller Services and Process Groups

# =======================================================
# OPTIONAL SCRIPT TO AUTOMATE TEMPLATE CREATION (YOU CAN AVOID THIS)
# =======================================================

set -e

NIFI_URL="https://localhost:8443/nifi-api"
NIFI_USERNAME="${NIFI_USERNAME:-superAdmin}"
NIFI_PASSWORD="${NIFI_PASSWORD:-password123}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================"
echo "NiFi Template Setup"
echo "========================================"

# Step 1: Authenticate
echo -e "\n${YELLOW}[1/6]${NC} Authenticating to NiFi..."
TOKEN=$(curl -k -s -X POST "$NIFI_URL/access/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$NIFI_USERNAME&password=$NIFI_PASSWORD")

if [ -z "$TOKEN" ]; then
    echo -e "${RED}      Authentication failed${NC}"
    exit 1
fi
echo -e "${GREEN}      Authenticated as $NIFI_USERNAME${NC}"

# Step 2: Get root process group ID
echo -e "\n${YELLOW}[2/6]${NC} Getting root process group..."
ROOT_PG_ID=$(curl -k -s -H "Authorization: Bearer $TOKEN" "$NIFI_URL/flow/process-groups/root" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}      Root PG ID: $ROOT_PG_ID${NC}"

# Step 3: Create Controller Services at root level
echo -e "\n${YELLOW}[3/6]${NC} Creating Controller Services..."

# Get root controller services endpoint
CONTROLLER_URL="$NIFI_URL/controller/controller-services"

# Create DBCPConnectionPool
echo -e "      Creating DBCPConnectionPool..."
DBCP_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "type": "org.apache.nifi.dbcp.DBCPConnectionPool",
    "bundle": {
      "group": "org.apache.nifi",
      "artifact": "nifi-dbcp-service-nar",
      "version": "2.0.0"
    },
    "name": "DBCPConnectionPool",
    "properties": {
      "Database Connection URL": "${db.connection.url}",
      "Database Driver Class Name": "${db.driver.class}",
      "Database Driver Location(s)": "/opt/custom/drivers",
      "Database User": "${db.username}",
      "Password": "${db.password}",
      "Max Wait Time": "500 millis",
      "Max Total Connections": "8",
      "Validation query": "SELECT 1"
    }
  }
}'

DBCP_RESULT=$(curl -k -s -X POST "$CONTROLLER_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$DBCP_PAYLOAD")

DBCP_ID=$(echo "$DBCP_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$DBCP_ID" ]; then
    echo -e "${RED}      Failed to create DBCPConnectionPool${NC}"
    echo "$DBCP_RESULT" | head -20
    exit 1
fi

echo -e "${GREEN}      DBCPConnectionPool created: $DBCP_ID${NC}"

# Create AvroReader
echo -e "      Creating AvroReader..."
AVRO_READER_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "type": "org.apache.nifi.avro.AvroReader",
    "bundle": {
      "group": "org.apache.nifi",
      "artifact": "nifi-record-serialization-services-nar",
      "version": "2.0.0"
    },
    "name": "AvroReader",
    "properties": {
      "Schema Access Strategy": "Embedded Avro Schema"
    }
  }
}'

AVRO_READER_RESULT=$(curl -k -s -X POST "$CONTROLLER_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$AVRO_READER_PAYLOAD")

AVRO_READER_ID=$(echo "$AVRO_READER_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$AVRO_READER_ID" ]; then
    echo -e "${RED}      Failed to create AvroReader${NC}"
    echo "$AVRO_READER_RESULT" | head -20
    exit 1
fi

echo -e "${GREEN}      AvroReader created: $AVRO_READER_ID${NC}"

# Create AvroRecordSetWriter
echo -e "      Creating AvroRecordSetWriter..."
AVRO_WRITER_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "type": "org.apache.nifi.avro.AvroRecordSetWriter",
    "bundle": {
      "group": "org.apache.nifi",
      "artifact": "nifi-record-serialization-services-nar",
      "version": "2.0.0"
    },
    "name": "AvroRecordSetWriter",
    "properties": {
      "Schema Write Strategy": "Embed Avro Schema",
      "Schema Access Strategy": "Inherit Record Schema",
      "Compression Format": "SNAPPY"
    }
  }
}'

AVRO_WRITER_RESULT=$(curl -k -s -X POST "$CONTROLLER_URL" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$AVRO_WRITER_PAYLOAD")

AVRO_WRITER_ID=$(echo "$AVRO_WRITER_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$AVRO_WRITER_ID" ]; then
    echo -e "${RED}      Failed to create AvroRecordSetWriter${NC}"
    echo "$AVRO_WRITER_RESULT" | head -20
    exit 1
fi

echo -e "${GREEN}      AvroRecordSetWriter created: $AVRO_WRITER_ID${NC}"

# Step 4: Controller Services created (NOT enabled yet)
echo -e "\n${YELLOW}[4/6]${NC} Controller Services created (not enabled)"
echo -e "${YELLOW}      You will enable them manually after setting variables${NC}"

# Step 5: Create OracleFlow Process Group
echo -e "\n${YELLOW}[5/6]${NC} Creating OracleFlow Process Group..."

PG_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "name": "OracleFlow",
    "position": {
      "x": 400,
      "y": 200
    }
  }
}'

PG_RESULT=$(curl -k -s -X POST "$NIFI_URL/process-groups/$ROOT_PG_ID/process-groups" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PG_PAYLOAD")

PG_ID=$(echo "$PG_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}      OracleFlow Process Group created: $PG_ID${NC}"

# Step 6: Create processors in OracleFlow
echo -e "\n${YELLOW}[6/6]${NC} Creating processors in OracleFlow..."

# Create ExecuteSQLRecord processor
echo -e "      Creating ExecuteSQLRecord..."
EXEC_SQL_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "type": "org.apache.nifi.processors.standard.ExecuteSQLRecord",
    "name": "ExecuteSQLRecord",
    "position": {"x": 100, "y": 100},
    "config": {
      "properties": {
        "dbcp-service": "'"$DBCP_ID"'",
        "sql-select-query": "SELECT * FROM YOUR_TABLE",
        "record-writer": "'"$AVRO_WRITER_ID"'",
        "querytimeout": "0 seconds",
        "max-rows-per-flow-file": "0"
      },
      "autoTerminatedRelationships": []
    }
  }
}'

EXEC_SQL_RESULT=$(curl -k -s -X POST "$NIFI_URL/process-groups/$PG_ID/processors" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$EXEC_SQL_PAYLOAD")

EXEC_SQL_ID=$(echo "$EXEC_SQL_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}      ExecuteSQLRecord created: $EXEC_SQL_ID${NC}"

# Create PutDatabaseRecord processor
echo -e "      Creating PutDatabaseRecord..."
PUT_DB_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "type": "org.apache.nifi.processors.standard.PutDatabaseRecord",
    "name": "PutDatabaseRecord",
    "position": {"x": 100, "y": 300},
    "config": {
      "properties": {
        "dbcp-service": "'"$DBCP_ID"'",
        "record-reader-factory": "'"$AVRO_READER_ID"'",
        "statement-type": "INSERT",
        "catalog-name": "",
        "schema-name": "",
        "table-name": "YOUR_TARGET_TABLE",
        "translate-field-names": "true",
        "unmatched-field-behavior": "Ignore Unmatched Fields",
        "unmatched-column-behavior": "Fail on Unmatched Columns",
        "update-keys": "",
        "field-containing-sql": "",
        "allow-multiple-statements": "false",
        "quote-identifiers": "false",
        "quote-table-identifiers": "false",
        "query-timeout": "0 seconds",
        "rollback-on-failure": "false",
        "batch-size": "100"
      },
      "autoTerminatedRelationships": ["success"]
    }
  }
}'

PUT_DB_RESULT=$(curl -k -s -X POST "$NIFI_URL/process-groups/$PG_ID/processors" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PUT_DB_PAYLOAD")

PUT_DB_ID=$(echo "$PUT_DB_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}      PutDatabaseRecord created: $PUT_DB_ID${NC}"

# Create connection between processors
echo -e "      Creating connection..."
CONN_PAYLOAD='{
  "revision": {"version": 0},
  "component": {
    "source": {
      "id": "'"$EXEC_SQL_ID"'",
      "groupId": "'"$PG_ID"'",
      "type": "PROCESSOR"
    },
    "destination": {
      "id": "'"$PUT_DB_ID"'",
      "groupId": "'"$PG_ID"'",
      "type": "PROCESSOR"
    },
    "selectedRelationships": ["success"]
  }
}'

curl -k -s -X POST "$NIFI_URL/process-groups/$PG_ID/connections" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CONN_PAYLOAD" > /dev/null

echo -e "${GREEN}      Connection created${NC}"

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nCreated Controller Services:"
echo -e "  - DBCPConnectionPool (ID: $DBCP_ID)"
echo -e "  - AvroReader (ID: $AVRO_READER_ID)"
echo -e "  - AvroRecordSetWriter (ID: $AVRO_WRITER_ID)"
echo -e "\nCreated Process Group:"
echo -e "  - OracleFlow (ID: $PG_ID)"
echo -e "    └── ExecuteSQLRecord → PutDatabaseRecord"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "1. ${YELLOW}SET NIFI VARIABLES (IMPORTANT):${NC}"
echo -e "   Right-click canvas → Variables → Add:"
echo -e "   ${GREEN}db.connection.url${NC} = jdbc:oracle:thin:@hostname:1521:SID"
echo -e "   ${GREEN}db.driver.class${NC} = oracle.jdbc.OracleDriver"
echo -e "   ${GREEN}db.username${NC} = your_username"
echo -e "   ${GREEN}db.password${NC} = your_password (mark as sensitive)"
echo -e ""
echo -e "2. ${YELLOW}ENABLE CONTROLLER SERVICES:${NC}"
echo -e "   Hamburger menu → Controller Settings → Controller Services"
echo -e "   Enable: DBCPConnectionPool, AvroReader, AvroRecordSetWriter"
echo -e ""
echo -e "3. Update SQL query in ExecuteSQLRecord"
echo -e "4. Update target table in PutDatabaseRecord"