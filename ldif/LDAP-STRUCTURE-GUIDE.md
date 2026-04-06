# LDAP Structure and NiFi Integration Guide

This document explains how LDAP is structured, how it integrates with NiFi authentication, and how to manage users and groups.

---

## Table of Contents

1. [LDAP Directory Structure](#ldap-directory-structure)
2. [Understanding the LDIF File](#understanding-the-ldif-file)
3. [How NiFi Uses LDAP](#how-nifi-uses-ldap)
4. [User and Group Management](#user-and-group-management)
5. [Adding New Users](#adding-new-users)
6. [Adding New Groups](#adding-new-groups)
7. [Troubleshooting](#troubleshooting)

---

## LDAP Directory Structure

LDAP (Lightweight Directory Access Protocol) organizes data in a hierarchical tree structure, similar to a file system.

### Your Directory Tree

```
dc=nifi,dc=local                          (Root - Domain Component)
├── ou=users,dc=nifi,dc=local            (Organizational Unit - Users)
│   ├── cn=superAdmin,ou=users,...       (User entry)
│   ├── cn=user1,ou=users,...            (User entry)
│   ├── cn=user2,ou=users,...            (User entry)
│   └── cn=user3,ou=users,...            (User entry)
└── ou=groups,dc=nifi,dc=local           (Organizational Unit - Groups)
    ├── cn=admins,ou=groups,...          (Group entry)
    ├── cn=teamA,ou=groups,...           (Group entry)
    └── cn=teamB,ou=groups,...           (Group entry)
```

### DN (Distinguished Name)

Every entry in LDAP has a unique identifier called a Distinguished Name (DN).

**Example:**
```
cn=user1,ou=users,dc=nifi,dc=local
```

This reads from right to left:
- `dc=local` - Domain component "local"
- `dc=nifi` - Domain component "nifi"
- `ou=users` - Organizational unit "users"
- `cn=user1` - Common name "user1"

Think of it like a file path: `/local/nifi/users/user1`

---

## Understanding the LDIF File

LDIF (LDAP Data Interchange Format) is a text format for representing LDAP entries. Your `init-users.ldif` file defines the initial directory structure and entries.

### File Structure

The file is divided into sections:

#### 1. Organizational Units (Containers)

```ldif
dn: ou=users,dc=nifi,dc=local
objectClass: organizationalUnit
ou: users
```

**Explanation:**
- `dn:` - The unique identifier for this entry
- `objectClass:` - The type of entry (organizationalUnit is a container)
- `ou:` - The name of the organizational unit

This creates a container to hold user entries.

#### 2. User Entries

```ldif
dn: cn=user1,ou=users,dc=nifi,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: user1
sn: User1
uid: user1
uidNumber: 10002
gidNumber: 5002
homeDirectory: /home/user1
userPassword: password123
```

**Field Breakdown:**

| Field | Purpose | Example | Notes |
|-------|---------|---------|-------|
| `dn` | Unique identifier | `cn=user1,ou=users,...` | Must be unique |
| `objectClass` | Entry type | `inetOrgPerson` | Can have multiple |
| `cn` | Common name | `user1` | Display name |
| `sn` | Surname | `User1` | Required by inetOrgPerson |
| `uid` | User ID | `user1` | Used for login |
| `uidNumber` | Numeric user ID | `10002` | Must be unique |
| `gidNumber` | Group ID | `5002` | Links user to primary group |
| `homeDirectory` | Home path | `/home/user1` | Unix-style home |
| `userPassword` | Password | `password123` | Plain text (LDAP hashes it) |

**ObjectClasses Explained:**
- `inetOrgPerson` - Standard person entry (requires cn, sn)
- `posixAccount` - Unix/Linux account attributes (uid, uidNumber, gidNumber)
- `shadowAccount` - Unix password aging info

#### 3. Group Entries

```ldif
dn: cn=teamA,ou=groups,dc=nifi,dc=local
objectClass: posixGroup
objectClass: groupOfNames
cn: teamA
gidNumber: 5002
member: cn=user1,ou=users,dc=nifi,dc=local
member: cn=user2,ou=users,dc=nifi,dc=local
```

**Field Breakdown:**

| Field | Purpose | Example | Notes |
|-------|---------|---------|-------|
| `dn` | Unique identifier | `cn=teamA,ou=groups,...` | Must be unique |
| `objectClass` | Entry type | `posixGroup` | Combines two types |
| `cn` | Group name | `teamA` | Display name |
| `gidNumber` | Group ID | `5002` | Must match user's gidNumber |
| `member` | Group members | `cn=user1,ou=users,...` | Full DN of user |

**ObjectClasses Explained:**
- `posixGroup` - Unix-style group (uses gidNumber)
- `groupOfNames` - LDAP group (uses member attribute)

**Why both?**
- `posixGroup` allows gidNumber-based membership (user's primary group)
- `groupOfNames` allows explicit member listing (secondary groups)

### Number Ranges

The file uses specific number ranges to avoid conflicts:

| Range | Purpose | Example |
|-------|---------|---------|
| 10001-10999 | User IDs (uidNumber) | superAdmin = 10001 |
| 5001-5999 | Group IDs (gidNumber) | admins = 5001 |

**Important:** Keep these ranges separate. Using the same number for uidNumber and gidNumber can cause confusion.

---

## How NiFi Uses LDAP

### Authentication Flow

When a user logs into NiFi:

```
1. User enters username and password in NiFi UI
   ↓
2. NiFi sends credentials to LDAP (ldap://openldap:389)
   ↓
3. LDAP searches for user: uid={username}
   - Search base: ou=users,dc=nifi,dc=local
   - Search filter: uid={0} (where {0} is replaced with username)
   ↓
4. If found, LDAP verifies password
   ↓
5. LDAP returns user's DN: cn=user1,ou=users,dc=nifi,dc=local
   ↓
6. NiFi checks authorizers.xml for this DN
   ↓
7. If DN exists in authorizers.xml, user is granted access
```

### Configuration Files

#### login-identity-providers.xml

This file tells NiFi how to connect to LDAP:

```xml
<property name="Url">ldap://openldap:389</property>
<property name="User Search Base">ou=users,dc=nifi,dc=local</property>
<property name="User Search Filter">uid={0}</property>
```

**What this means:**
- Connect to LDAP server at `openldap:389`
- Look for users under `ou=users,dc=nifi,dc=local`
- Match username against `uid` attribute

**Example:** When user enters "user1":
- NiFi searches: `uid=user1` under `ou=users,dc=nifi,dc=local`
- Finds: `cn=user1,ou=users,dc=nifi,dc=local`
- Uses this DN for authentication

#### authorizers.xml

This file lists which LDAP users can access NiFi:

```xml
<property name="Initial User Identity 1">cn=superAdmin,ou=users,dc=nifi,dc=local</property>
<property name="Initial User Identity 2">cn=user1,ou=users,dc=nifi,dc=local</property>
```

**Critical:** The DN format must EXACTLY match what LDAP returns.

When NiFi starts, it:
1. Reads these DNs from authorizers.xml
2. Creates user records in users.xml
3. Creates default policies in authorizations.xml

---

## User and Group Management

### Using phpLDAPadmin

phpLDAPadmin provides a web UI for managing LDAP at http://localhost:8081

**Login credentials:**
- Login DN: `cn=admin,dc=nifi,dc=local`
- Password: `admin`

### Understanding Group Membership

There are two types of group membership:

#### 1. Primary Group (gidNumber)

Each user has ONE primary group set by `gidNumber`:

```ldif
dn: cn=user1,ou=users,dc=nifi,dc=local
gidNumber: 5002        # Primary group: teamA (gidNumber 5002)
```

**Use case:** Default group for file ownership, primary team assignment.

#### 2. Secondary Groups (member attribute)

Users can belong to multiple groups via the `member` attribute:

```ldif
dn: cn=teamA,ou=groups,dc=nifi,dc=local
gidNumber: 5002
member: cn=user1,ou=users,dc=nifi,dc=local
member: cn=user2,ou=users,dc=nifi,dc=local
```

**Use case:** Additional team memberships, cross-functional groups.

### Current Group Assignments

| User | Primary Group (gidNumber) | Member Of |
|------|---------------------------|-----------|
| superAdmin | admins (5001) | admins |
| user1 | teamA (5002) | teamA |
| user2 | teamA (5002) | teamA |
| user3 | teamB (5003) | teamB |

---

## Adding New Users

### Method 1: Via phpLDAPadmin (GUI)

1. Navigate to http://localhost:8081
2. Login as admin
3. Click on `ou=users,dc=nifi,dc=local`
4. Click **"Create a child entry"**
5. Select **"Generic: User Account"**
6. Fill in the form:
   - **RDN:** `cn`
   - **cn:** `user4`
   - **uid:** `user4`
   - **sn:** `User4`
   - **uidNumber:** `10005` (must be unique)
   - **gidNumber:** `5002` (for teamA) or `5003` (for teamB) or `5001` (for admins)
   - **Home Directory:** `/home/user4`
   - **Password:** (enter password)
7. Click **"Create Object"**

### Method 2: Via LDIF File

Add to `ldif/init-users.ldif`:

```ldif
dn: cn=user4,ou=users,dc=nifi,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: user4
sn: User4
uid: user4
uidNumber: 10005
gidNumber: 5002
homeDirectory: /home/user4
userPassword: password123
```

Then reload:

```bash
docker exec nifi-openldap ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif
```

### Method 3: Command Line

```bash
docker exec nifi-openldap ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin << EOF
dn: cn=user4,ou=users,dc=nifi,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: user4
sn: User4
uid: user4
uidNumber: 10005
gidNumber: 5002
homeDirectory: /home/user4
userPassword: password123
EOF
```

### Adding User to NiFi

After creating the user in LDAP, you must add them to NiFi:

1. Stop NiFi: `docker-compose stop nifi`
2. Edit `nifi-config-backup/authorizers.xml`
3. Add the new user DN:
   ```xml
   <property name="Initial User Identity 5">cn=user4,ou=users,dc=nifi,dc=local</property>
   ```
4. Copy file to container:
   ```bash
   docker cp nifi-config-backup/authorizers.xml nifi:/opt/nifi/nifi-current/conf/
   ```
5. Delete old auth files:
   ```bash
   docker exec nifi rm -f /opt/nifi/nifi-current/conf/users.xml
   docker exec nifi rm -f /opt/nifi/nifi-current/conf/authorizations.xml
   ```
6. Start NiFi: `docker-compose start nifi`

---

## Adding New Groups

### Method 1: Via phpLDAPadmin

1. Navigate to http://localhost:8081
2. Login as admin
3. Click on `ou=groups,dc=nifi,dc=local`
4. Click **"Create a child entry"**
5. Select **"Generic: Posix Group"**
6. Fill in:
   - **cn:** `teamC`
   - **gidNumber:** `5004` (must be unique)
7. Click **"Create Object"**
8. Click **"Add new attribute"**
9. Select **"objectClass"**
10. Add value: `groupOfNames`
11. Click **"Add new attribute"**
12. Select **"member"**
13. Enter member DN: `cn=user4,ou=users,dc=nifi,dc=local`
14. Click **"Update Object"**

### Method 2: Via LDIF File

Add to `ldif/init-users.ldif`:

```ldif
dn: cn=teamC,ou=groups,dc=nifi,dc=local
objectClass: posixGroup
objectClass: groupOfNames
cn: teamC
gidNumber: 5004
member: cn=user4,ou=users,dc=nifi,dc=local
```

### Assigning Users to Groups

To add a user to an existing group:

1. In phpLDAPadmin, navigate to the group (e.g., `cn=teamA`)
2. Click **"Add new attribute"**
3. Select **"member"**
4. Enter the user's full DN: `cn=user4,ou=users,dc=nifi,dc=local`
5. Click **"Update Object"**

---

## Troubleshooting

### User Cannot Login to NiFi

**Symptom:** "Bad credentials" error

**Check 1: User exists in LDAP**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" -D "cn=admin,dc=nifi,dc=local" -w admin uid=user1
```

Expected output: Should show the user entry

**Check 2: uid matches username**

In LDAP:
```ldif
uid: user1        # This is what you type in NiFi login
cn: user1         # This is the common name
```

NiFi searches by `uid`, not `cn`.

**Check 3: DN exists in authorizers.xml**

The user's DN must be listed in `nifi-config-backup/authorizers.xml`:

```bash
docker exec nifi cat /opt/nifi/nifi-current/conf/authorizers.xml | grep "user1"
```

Expected output:
```xml
<property name="Initial User Identity 2">cn=user1,ou=users,dc=nifi,dc=local</property>
```

### User Can Login But Has No Permissions

**Symptom:** "Unable to view the user interface"

**Cause:** User exists but has no policies assigned.

**Solution:**

As `superAdmin`:
1. Login to NiFi
2. Click hamburger menu → **Policies**
3. Select **"view the user interface"**
4. Click **+** and add the user
5. Select **"access the controller"**
6. Click **+** and add the user

### Group Not Showing in phpLDAPadmin

**Symptom:** Groups section shows (1) instead of (3)

**Cause:** Duplicate DN entries in LDIF file

**Solution:** Ensure each group is defined ONCE with both objectClasses:

```ldif
# CORRECT - One entry with both objectClasses
dn: cn=teamA,ou=groups,dc=nifi,dc=local
objectClass: posixGroup
objectClass: groupOfNames
cn: teamA
gidNumber: 5002
member: cn=user1,ou=users,dc=nifi,dc=local

# WRONG - Two entries with same DN
dn: cn=teamA,ou=groups,dc=nifi,dc=local
objectClass: posixGroup
...

dn: cn=teamA,ou=groups,dc=nifi,dc=local  # Duplicate DN!
objectClass: groupOfNames
...
```

### LDAP Connection Failed

**Symptom:** NiFi logs show "Connection refused" or "Cannot connect to LDAP"

**Check 1: LDAP container is running**
```bash
docker ps | grep openldap
```

**Check 2: LDAP port is accessible**
```bash
docker exec nifi nc -zv openldap 389
```

Expected output: `Connection to openldap 389 port [tcp/ldap] succeeded!`

**Check 3: Network connectivity**
```bash
docker exec nifi ping openldap
```

**Check 4: LDAP service is responding**
```bash
docker exec nifi-openldap ldapsearch -x -b "dc=nifi,dc=local" -LLL
```

Should return directory entries.

### Numbers Already in Use

**Symptom:** "Already exists" or "Constraint violation" when adding user/group

**Cause:** uidNumber or gidNumber already used

**Solution:** Use unique numbers:

**Check existing uidNumbers:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" uidNumber | grep uidNumber
```

**Check existing gidNumbers:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=groups,dc=nifi,dc=local" gidNumber | grep gidNumber
```

Pick a number not in the list.

---

## Best Practices

### Number Assignment

- **uidNumbers:** Start at 10001, increment by 1
- **gidNumbers:** Start at 5001, increment by 1
- Keep ranges separate to avoid confusion

### Password Management

- Default passwords are in plain text in LDIF
- LDAP automatically hashes them when stored
- Change default passwords immediately in production
- Use phpLDAPadmin to change passwords (hashes automatically)

### Group Strategy

**Primary Group (gidNumber):**
- Use for main team assignment
- Each user has exactly one
- Example: user1 → teamA (5002)

**Secondary Groups (member):**
- Use for additional roles
- Users can have multiple
- Example: user1 is also in "developers" group

### DN Naming Convention

Keep DN format consistent:
- Users: `cn={username},ou=users,dc=nifi,dc=local`
- Groups: `cn={groupname},ou=groups,dc=nifi,dc=local`

This makes it easier to:
- Write scripts
- Troubleshoot issues
- Maintain consistency

### Backup

Regularly export LDAP data:

```bash
docker exec nifi-openldap slapcat -n 1 > ldap-backup-$(date +%Y%m%d).ldif
```

Restore if needed:

```bash
docker-compose down -v
docker-compose up -d openldap
docker exec nifi-openldap slapadd -n 1 -l ldap-backup-20260215.ldif
docker-compose restart openldap
```

---

## Reference

### Useful LDAP Commands

**Search all users:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" -LLL
```

**Search all groups:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=groups,dc=nifi,dc=local" -LLL
```

**Search specific user:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" uid=user1 -LLL
```

**Check group membership:**
```bash
docker exec nifi-openldap ldapsearch -x -b "ou=groups,dc=nifi,dc=local" cn=teamA -LLL
```

**Delete user:**
```bash
docker exec nifi-openldap ldapdelete -x -D "cn=admin,dc=nifi,dc=local" -w admin "cn=user4,ou=users,dc=nifi,dc=local"
```

**Modify user password:**
```bash
docker exec nifi-openldap ldappasswd -x -D "cn=admin,dc=nifi,dc=local" -w admin -s newpassword "cn=user1,ou=users,dc=nifi,dc=local"
```

### Important File Locations

| File | Location | Purpose |
|------|----------|---------|
| init-users.ldif | `./ldif/init-users.ldif` | Initial LDAP data |
| login-identity-providers.xml | `./nifi-config-backup/` | NiFi LDAP connection |
| authorizers.xml | `./nifi-config-backup/` | NiFi user authorization |
| LDAP data (in container) | `/var/lib/ldap` | LDAP database |

### Port Reference

| Port | Service | URL |
|------|---------|-----|
| 389 | OpenLDAP | ldap://localhost:389 |
| 8081 | phpLDAPadmin | http://localhost:8081 |
| 8443 | NiFi | https://localhost:8443/nifi |
| 18080 | NiFi Registry | http://localhost:18080 |

---

## Additional Resources

- [LDAP Documentation](https://www.openldap.org/doc/)
- [NiFi LDAP Configuration](https://nifi.apache.org/docs/nifi-docs/html/administration-guide.html#ldap_login_identity_provider)
- [phpLDAPadmin Documentation](http://phpldapadmin.sourceforge.net/wiki/index.php/Main_Page)
- [LDIF Format Specification](https://tools.ietf.org/html/rfc2849)
