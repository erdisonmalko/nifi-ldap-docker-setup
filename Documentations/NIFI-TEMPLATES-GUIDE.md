# NiFi Templates Setup Guide

This guide explains how to automatically set up Controller Services and Oracle Flow templates in NiFi.

## What Gets Created

### Controller Services (Root Level)
1. **DBCPConnectionPool** - Database connection pool for Oracle/SQL Server
2. **AvroReader** - Reads data in Avro format
3. **AvroRecordSetWriter** - Writes data in Avro format with Snappy compression

### Process Groups
1. **OracleFlow** - Contains:
   - **ExecuteSQLRecord** - Queries database and outputs records
   - **PutDatabaseRecord** - Writes records back to database
   - Connection between them

## Prerequisites

### 1. Database Drivers

Place your JDBC drivers in the `./drivers/` folder:

**Oracle:**
```bash
# Download ojdbc8.jar or ojdbc11.jar from Oracle
cp ojdbc8.jar ./drivers/
```

**SQL Server:**
```bash
# Download mssql-jdbc from Microsoft
cp mssql-jdbc-12.2.0.jre11.jar ./drivers/
```

**PostgreSQL:**
```bash
# Download from PostgreSQL JDBC
cp postgresql-42.6.0.jar ./drivers/
```

### 2. Environment Variables

Create `.env` file from template:

```bash
cp .env.template .env
# Edit .env with your database credentials
nano .env
```

Example `.env` for Oracle:
```properties
DB_CONNECTION_URL=jdbc:oracle:thin:@mydb.example.com:1521:ORCL
DB_DRIVER_CLASS=oracle.jdbc.OracleDriver
DB_USERNAME=myuser
DB_PASSWORD=mypassword
```

Example `.env` for SQL Server:
```properties
DB_CONNECTION_URL=jdbc:sqlserver://mydb.example.com:1433;databaseName=mydb
DB_DRIVER_CLASS=com.microsoft.sqlserver.jdbc.SQLServerDriver
DB_USERNAME=myuser
DB_PASSWORD=mypassword
```

## Automated Setup

Run the setup script:

```bash
bash scripts/setup-nifi-templates.sh
```

This will:
1. Authenticate to NiFi as superAdmin
2. Create 3 Controller Services at root level
3. Enable all Controller Services
4. Create OracleFlow Process Group
5. Create ExecuteSQLRecord and PutDatabaseRecord processors
6. Connect them together

**Output:**
```
========================================
NiFi Template Setup
========================================

[1/6] Authenticating to NiFi...
      Authenticated as superAdmin

[2/6] Getting root process group...
      Root PG ID: abc123...

[3/6] Creating Controller Services...
      Creating DBCPConnectionPool...
      DBCPConnectionPool created: cs-001
      Creating AvroReader...
      AvroReader created: cs-002
      Creating AvroRecordSetWriter...
      AvroRecordSetWriter created: cs-003

[4/6] Enabling Controller Services...
      All Controller Services enabled

[5/6] Creating OracleFlow Process Group...
      OracleFlow Process Group created: pg-001

[6/6] Creating processors in OracleFlow...
      Creating ExecuteSQLRecord...
      ExecuteSQLRecord created: proc-001
      Creating PutDatabaseRecord...
      PutDatabaseRecord created: proc-002
      Connection created

========================================
Setup Complete!
========================================
```

## Manual Configuration

After running the script, configure NiFi variables to use your `.env` values:

### Step 1: Set NiFi Variables

1. Right-click on canvas → **Variables**
2. Click **+** to add variables:
   - `db.connection.url` = `jdbc:oracle:thin:@mydb:1521:ORCL`
   - `db.driver.class` = `oracle.jdbc.OracleDriver`
   - `db.username` = `myuser`
   - `db.password` = `mypassword`
3. Click **Apply**

### Step 2: Configure ExecuteSQLRecord

1. Double-click **OracleFlow** Process Group
2. Right-click **ExecuteSQLRecord** → **Configure**
3. In **Properties** tab:
   - **SQL select query:** `SELECT * FROM EMPLOYEES WHERE hire_date > SYSDATE - 7`
   - (Query will use the DBCPConnectionPool automatically)
4. Click **Apply**

### Step 3: Configure PutDatabaseRecord

1. Right-click **PutDatabaseRecord** → **Configure**
2. In **Properties** tab:
   - **Table Name:** `EMPLOYEES_ARCHIVE`
   - **Statement Type:** `INSERT` (or `UPDATE`, `UPSERT`)
3. Click **Apply**

### Step 4: Test the Flow

1. Right-click **ExecuteSQLRecord** → **Run Once**
2. Check queue between processors
3. Right-click **PutDatabaseRecord** → **Run Once**
4. Verify data in target table

## Controller Service Details

### DBCPConnectionPool Properties

| Property | Value | Description |
|----------|-------|-------------|
| Database Connection URL | `${db.connection.url}` | JDBC URL from variables |
| Database Driver Class Name | `${db.driver.class}` | Driver class from variables |
| Database Driver Location(s) | `/opt/custom/drivers` | Where JAR files are mounted |
| Database User | `${db.username}` | Username from variables |
| Password | `${db.password}` | Password from variables |
| Max Total Connections | `8` | Connection pool size |
| Validation query | `SELECT 1` | Health check query |

**Why use variables?**
- No passwords hardcoded in configuration
- Easy to update credentials
- Can be different per environment (dev/test/prod)

### AvroReader Properties

| Property | Value | Description |
|----------|-------|-------------|
| Schema Access Strategy | `Embedded Avro Schema` | Schema is in the Avro file |

### AvroRecordSetWriter Properties

| Property | Value | Description |
|----------|-------|-------------|
| Schema Write Strategy | `Embed Avro Schema` | Include schema in output |
| Schema Access Strategy | `Inherit Record Schema` | Use incoming schema |
| Compression Format | `SNAPPY` | Fast compression |

## Common Use Cases

### Use Case 1: Copy Data Between Tables

```
ExecuteSQLRecord (SELECT * FROM source_table)
    ↓
PutDatabaseRecord (INSERT INTO target_table)
```

### Use Case 2: Extract, Transform, Load

```
ExecuteSQLRecord (SELECT * FROM source)
    ↓
UpdateRecord (Transform data)
    ↓
PutDatabaseRecord (INSERT INTO target)
```

### Use Case 3: Change Data Capture

```
ExecuteSQLRecord (SELECT * WHERE modified_date > ?)
    ↓
RouteOnAttribute (Route by change type)
    ↓
PutDatabaseRecord (INSERT/UPDATE/DELETE)
```

## Troubleshooting

### Controller Service won't enable

**Error:** "Cannot enable because missing driver"

**Solution:**
1. Check drivers are in `./drivers/` folder
2. Verify folder is mounted: `docker exec nifi ls /opt/custom/drivers`
3. Restart NiFi: `docker-compose restart nifi`

### Database connection fails

**Error:** "Unable to obtain connection"

**Check:**
1. Verify credentials in Variables
2. Test connection from database client
3. Check firewall/network access
4. Verify driver class name matches driver version

```bash
# Test Oracle connection
sqlplus myuser/mypassword@mydb:1521/ORCL

# Test SQL Server connection
sqlcmd -S mydb -U myuser -P mypassword
```

### Processors show validation errors

**Error:** "ExecuteSQLRecord is invalid"

**Solution:**
1. Ensure DBCPConnectionPool is **ENABLED** (green checkmark)
2. Check all required properties are set
3. Verify SQL query syntax
4. Check table/column names exist

### Variables not resolving

**Error:** "${db.connection.url} is not a valid URL"

**Solution:**
1. Variables must be set at Process Group level
2. Right-click canvas → Variables → Verify values
3. No spaces in variable names
4. Variable names are case-sensitive

## Advanced: Multiple Databases

To connect to multiple databases:

1. Create separate DBCPConnectionPool for each database:
   - `DBCPConnectionPool-Oracle`
   - `DBCPConnectionPool-SQLServer`
   - `DBCPConnectionPool-Postgres`

2. Use different variable names:
   ```
   oracle.connection.url
   sqlserver.connection.url
   postgres.connection.url
   ```

3. Point each processor to the correct connection pool

## Integration with LDAP Users

Controller Services are **shared** across all users, but you can control access:

### Option 1: Global Services (Current Setup)
- All users can use the same database connection
- Simplest for teams sharing data sources

### Option 2: Per-Team Services
1. Create Controller Services inside team Process Groups
2. Set access policies per Process Group
3. Team A has "Oracle-TeamA-DB"
4. Team B has "Oracle-TeamB-DB"

## Backup and Version Control

### Save Configuration as Template

1. Right-click **OracleFlow** → **Create template**
2. Name: `Oracle-ETL-Template`
3. Download template (hamburger menu → Templates)
4. Commit to git

### Export Controller Services

```bash
# Get Controller Service IDs
curl -k -u superAdmin:password123 https://localhost:8443/nifi-api/flow/process-groups/root/controller-services

# Export configuration
curl -k -u superAdmin:password123 https://localhost:8443/nifi-api/controller-services/{id} > dbcp-config.json
```

## Cleanup

To remove everything created by the script:

1. Stop and delete OracleFlow Process Group
2. Disable Controller Services (hamburger menu → Controller Settings)
3. Delete Controller Services

Or use the API:

```bash
# Delete Process Group
curl -k -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8443/nifi-api/process-groups/{pg-id}?version=1"

# Disable and delete Controller Services
curl -k -X PUT -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8443/nifi-api/controller-services/{cs-id}/run-status" \
  -d '{"state":"DISABLED"}'

curl -k -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8443/nifi-api/controller-services/{cs-id}?version=1"
```

## Production Recommendations

1. **Use connection pooling:** Set Max Total Connections based on load
2. **Set timeouts:** Configure query timeout to prevent hanging
3. **Monitor connections:** Use NiFi's built-in monitoring
4. **Secure passwords:** Use encrypted variables or parameter contexts
5. **Test rollback:** Enable "Rollback on Failure" for critical flows
6. **Batch operations:** Use batch-size property for better performance
7. **Health checks:** Configure validation queries for all connection pools

## Next Steps

1. Run the setup script
2. Configure your database variables
3. Test with a simple query
4. Add error handling (UpdateAttribute, RouteOnAttribute)
5. Add logging (LogAttribute processors)
6. Version control your flow
7. Set up monitoring and alerts
