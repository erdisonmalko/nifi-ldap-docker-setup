# NiFi Multi-User Docker Setup

Complete guide to set up Apache NiFi with LDAP authentication for multi-user environments.

## Quick Start

```powershell
git clone <your-repo>
cd nifi-docker
.\scripts\windows\setup-nifi.ps1
```

Wait 5 minutes. Done.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [What You Get](#what-you-get)
3. [Automated Setup](#automated-setup)
4. [Manual Setup (If Script Fails)](#manual-setup-if-script-fails)
5. [Understanding the Configuration](#understanding-the-configuration)
6. [Common Operations](#common-operations)
7. [Troubleshooting](#troubleshooting)
8. [Architecture](#architecture)

---

## Prerequisites

- Docker Desktop installed and running
- Windows PowerShell
- 8GB RAM minimum
- Ports available: 389, 8081, 8443, 18080

---

## What You Get

After setup completes:

| Service | URL | Purpose |
|---------|-----|---------|
| NiFi | https://localhost:8443/nifi | Main application |
| LDAP Admin | http://localhost:8081 | Manage users |
| NiFi Registry | http://localhost:18080 | Version control |

**Users created:**
- `superAdmin` / `password123` (admin)
- `user1` / `password123` (Team A)
- `user2` / `password123` (Team A)
- `user3` / `password123` (Team B)

---

## Automated Setup

Run the setup script:

```powershell
.\scripts\windows\setup-nifi.ps1
```

The script will:
1. Clean up any existing containers
2. Start all services (NiFi, OpenLDAP, Registry, phpLDAPadmin)
3. Create LDAP users
4. Wait for NiFi to generate SSL certificates
5. Stop NiFi temporarily
6. Apply LDAP configuration from `nifi-config-backup/`
7. Restart NiFi with multi-user authentication

Total time: 5-7 minutes

---

## Manual Setup (If Script Fails)

If the automated script fails, follow these steps manually:

### Step 1: Start Services

```powershell
docker-compose up -d
```

Wait 2-3 minutes for all services to start.

### Step 2: Create LDAP Users

```powershell
docker exec nifi-openldap ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif
```

If you see "Already exists (68)" - that's fine, users are already created.

### Step 3: Wait for NiFi Initial Startup

Check logs until you see "Started Server on":

```powershell
docker-compose logs -f nifi
```

Press Ctrl+C when you see the startup message.

### Step 4: Stop NiFi

```powershell
docker-compose stop nifi
```

### Step 5: Apply LDAP Configuration

Copy the pre-configured files:

```powershell
docker cp nifi-config-backup\login-identity-providers.xml nifi:/opt/nifi/nifi-current/conf/
docker cp nifi-config-backup\authorizers.xml nifi:/opt/nifi/nifi-current/conf/
docker cp nifi-config-backup\nifi.properties nifi:/opt/nifi/nifi-current/conf/
```

Delete old single-user auth files:

```powershell
docker exec nifi rm -f /opt/nifi/nifi-current/conf/users.xml
docker exec nifi rm -f /opt/nifi/nifi-current/conf/authorizations.xml
```

### Step 6: Start NiFi with LDAP

```powershell
docker-compose start nifi
```

Wait 2-3 minutes. Check logs:

```powershell
docker-compose logs -f nifi
```

Look for "Started Server on https://..."

### Step 7: Login

Go to https://localhost:8443/nifi

Login as `superAdmin` / `password123`

---

## Understanding the Configuration

### Why We Have Three Config Files

The setup uses 3 pre-configured files in `nifi-config-backup/`:

#### 1. login-identity-providers.xml
**What it does:** Tells NiFi how to authenticate users

**Key settings:**
- LDAP server: `ldap://openldap:389`
- Search base: `ou=users,dc=nifi,dc=local`
- Search filter: `uid={0}` (matches username to LDAP uid)

**Why we need it:** Without this, NiFi only supports single-user login

#### 2. authorizers.xml
**What it does:** Defines which users exist and who has admin rights

**Key sections:**

```xml
<!-- List all users that will be in the system -->
<property name="Initial User Identity 1">cn=superAdmin,ou=users,dc=nifi,dc=local</property>
<property name="Initial User Identity 2">cn=user1,ou=users,dc=nifi,dc=local</property>
<property name="Initial User Identity 3">cn=user2,ou=users,dc=nifi,dc=local</property>
<property name="Initial User Identity 4">cn=user3,ou=users,dc=nifi,dc=local</property>

<!-- Who is the admin -->
<property name="Initial Admin Identity">cn=superAdmin,ou=users,dc=nifi,dc=local</property>
```

**Why we need it:** This creates user records in NiFi and grants admin rights

**Important:** The user DN format `cn=superAdmin,ou=users,dc=nifi,dc=local` must match exactly what LDAP returns.

#### 3. nifi.properties
**What it does:** Main NiFi configuration (1000+ settings)

**We only change 2 lines:**

```properties
# Change from single-user to LDAP
nifi.security.user.login.identity.provider=ldap-provider

# Change from single-user to managed authorization
nifi.security.user.authorizer=managed-authorizer
```

**Why we need the whole file:** NiFi auto-generates SSL certificates and passwords in this file. If we only copy 2 lines, we lose the auto-generated keystore password and NiFi won't start.

### Why We Delete users.xml and authorizations.xml

When NiFi starts the first time, it's in single-user mode and creates:
- `users.xml` - Contains just the admin user
- `authorizations.xml` - Contains policies for admin user only

When we switch to LDAP mode, these files are outdated. We delete them so NiFi recreates them based on the users listed in `authorizers.xml`.

### The Startup Sequence

```
1. Start NiFi (single-user mode)
   -> Generates SSL keystore with random password
   -> Creates users.xml (single user)
   -> Creates authorizations.xml (single user policies)

2. Stop NiFi

3. Replace 3 config files
   -> login-identity-providers.xml (enable LDAP)
   -> authorizers.xml (list all LDAP users)
   -> nifi.properties (switch to LDAP mode, keeps keystore password)

4. Delete users.xml and authorizations.xml
   -> Forces NiFi to recreate these from authorizers.xml

5. Start NiFi (LDAP mode)
   -> Reads authorizers.xml
   -> Creates users.xml with all 4 users
   -> Creates authorizations.xml with policies for all users
   -> Connects to LDAP for authentication
```

---

## Common Operations

### Add a New User

1. Add user to LDAP via phpLDAPadmin (http://localhost:8081)
   - Login: `cn=admin,dc=nifi,dc=local` / `admin`
   - Navigate to `ou=users,dc=nifi,dc=local`
   - Create new entry (copy existing user as template)

2. Stop NiFi:
   ```powershell
   docker-compose stop nifi
   ```

3. Edit `nifi-config-backup\authorizers.xml` and add:
   ```xml
   <property name="Initial User Identity 5">cn=user4,ou=users,dc=nifi,dc=local</property>
   ```

4. Copy updated file:
   ```powershell
   docker cp nifi-config-backup\authorizers.xml nifi:/opt/nifi/nifi-current/conf/
   ```

5. Delete old auth files:
   ```powershell
   docker exec nifi rm -f /opt/nifi/nifi-current/conf/users.xml
   docker exec nifi rm -f /opt/nifi/nifi-current/conf/authorizations.xml
   ```

6. Start NiFi:
   ```powershell
   docker-compose start nifi
   ```

### Grant UI Access to Users

After first login as `superAdmin`:

1. Click hamburger menu (top right) -> Policies
2. Select "view the user interface"
3. Click + icon
4. Add `user1`, `user2`, `user3`
5. Select "access the controller"
6. Click + icon
7. Add `user1`, `user2`, `user3`

Now all users can login.

### Create Team Workspaces

1. Login as `superAdmin`
2. Drag "Process Group" from toolbar to canvas
3. Name it "Team A Projects"
4. Right-click -> Access policies
5. For each policy, click "Override" then add `user1` and `user2`
6. Repeat for "Team B Projects" with `user3`

Now teams have isolated workspaces.

### View Logs

```powershell
# All services
docker-compose logs -f

# Just NiFi
docker-compose logs -f nifi

# Just LDAP
docker-compose logs -f openldap
```

### Restart Services

```powershell
# Restart everything
docker-compose restart

# Restart just NiFi
docker-compose restart nifi
```

### Stop Everything

```powershell
# Stop (keeps data)
docker-compose down

# Stop and delete all data
docker-compose down -v
```

---

## Troubleshooting

### Script Fails at "NiFi failed to start"

**Symptom:** Script times out waiting for NiFi

**Check:** 
```powershell
docker-compose logs nifi | Select-String -Pattern "ERROR|Exception"
```

**Common causes:**

1. **Port 8443 already in use**
   ```powershell
   netstat -ano | findstr :8443
   ```
   Solution: Stop the process using that port

2. **Not enough memory**
   - Docker needs 8GB RAM minimum
   - Check Docker Desktop -> Settings -> Resources

3. **Keystore password mismatch**
   - This happens if you manually edited nifi.properties incorrectly
   - Solution: Run `docker-compose down -v` and start fresh

### Can't Login with LDAP Users

**Symptom:** "Bad credentials" error

**Check LDAP users exist:**
```powershell
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" -D "cn=admin,dc=nifi,dc=local" -w admin
```

You should see all 4 users listed.

**Check NiFi is using LDAP:**
```powershell
docker exec nifi cat /opt/nifi/nifi-current/conf/nifi.properties | findstr ldap
```

Should show: `nifi.security.user.login.identity.provider=ldap-provider`

**Check NiFi logs for LDAP errors:**
```powershell
docker-compose logs nifi | Select-String "ldap"
```

### Users Can Login But Have No Permissions

**Symptom:** "Unable to view the user interface" error

**Cause:** User exists but has no policies assigned

**Solution:** Login as `superAdmin` and grant UI access (see "Grant UI Access to Users" above)

### OpenLDAP Won't Start

**Symptom:** Script fails at "OpenLDAP failed to start"

**Check logs:**
```powershell
docker-compose logs openldap
```

**Common issue:** Leftover data from previous run

**Solution:**
```powershell
docker-compose down -v
docker volume rm nifi-docker_openldap-data
docker-compose up -d
```

### Container Shows "Exited"

**Check status:**
```powershell
docker-compose ps
```

**Restart the container:**
```powershell
docker-compose restart <container-name>
```

**Check why it exited:**
```powershell
docker-compose logs <container-name>
```

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                        │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   OpenLDAP   │  │     NiFi     │  │    NiFi      │ │
│  │   :389       │◄─┤   :8443      │◄─┤   Registry   │ │
│  │              │  │              │  │   :18080     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         │                                               │
│  ┌──────────────┐                                      │
│  │phpLDAPadmin │                                       │
│  │   :8081     │                                       │
│  └──────────────┘                                      │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

**User Login:**
```
1. User enters username/password in NiFi UI
2. NiFi sends credentials to OpenLDAP
3. LDAP verifies credentials
4. NiFi checks authorizations.xml for user policies
5. User granted access based on policies
```

**User Management:**
```
1. Admin creates user in LDAP (via phpLDAPadmin)
2. Admin adds user DN to authorizers.xml
3. Admin restarts NiFi
4. NiFi creates user record in users.xml
5. Admin assigns policies to user in NiFi UI
```

### File Structure

```
nifi-docker/
├── docker-compose.yml              # Defines all services
├── scripts/
│   └── windows/
│       └── setup-nifi.ps1          # Automated setup
├── ldif/
│   └── init-users.ldif             # LDAP user definitions
└── nifi-config-backup/             # Pre-configured files
    ├── login-identity-providers.xml
    ├── authorizers.xml
    └── nifi.properties
```

### Volumes (Persistent Data)

- `nifi-conf` - NiFi configuration files
- `nifi-database` - Flow definitions
- `nifi-content` - FlowFile content
- `nifi-provenance` - Data lineage
- `openldap-data` - LDAP user database
- `registry-data` - Registry database
- `registry-flows` - Versioned flows

To backup everything:
```powershell
docker-compose down
# Copy entire directory to backup location
# Restart when needed
docker-compose up -d
```

---

## Production Considerations

For production deployment:

1. **Change all passwords** in `ldif/init-users.ldif`
2. **Use proper SSL certificates** (not self-signed)
3. **Enable TLS for LDAP** in `docker-compose.yml`
4. **Restrict exposed ports** (use firewall/security groups)
5. **Set up automated backups** of Docker volumes
6. **Monitor logs** for security events
7. **Use secrets management** for passwords (not hardcoded)
8. **Scale resources** based on workload

---

## Getting Help

- **NiFi Issues:** Check logs with `docker-compose logs nifi`
- **LDAP Issues:** Check logs with `docker-compose logs openldap`
- **Container Issues:** Check status with `docker-compose ps`

For NiFi documentation: https://nifi.apache.org/docs.html
