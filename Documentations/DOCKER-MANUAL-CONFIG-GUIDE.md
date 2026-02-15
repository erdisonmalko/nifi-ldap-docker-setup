# Docker NiFi Setup - Manual Configuration Method

This approach gives you full control over configuration files, just like the ZIP version.

## 🎯 Strategy

1. Start NiFi with default single-user auth
2. Let NiFi generate its config files
3. Stop NiFi
4. Update config files manually
5. Restart with LDAP enabled

## 📝 Step-by-Step Setup

### Step 1: Clean Start

```powershell
cd C:\Users\user\Desktop\nifi-docker

# Remove any existing containers and volumes
docker-compose down -v

# Make sure ldif folder has the init-users.ldif file
dir ldif
```

### Step 2: Start Services

```powershell
# Start everything
docker-compose up -d

# Watch logs to see when NiFi is ready (wait 2-3 minutes)
docker-compose logs -f nifi
```

Wait until you see: `JettyServer NiFi has started`

### Step 3: Initialize LDAP Users

```powershell
# Initialize LDAP with users
docker exec nifi-openldap ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif
```

You should see success messages for each user created.

### Step 4: Verify NiFi is Running

Open: https://localhost:8443/nifi

Login with:
- Username: `admin`
- Password: `adminpassword123`

You should see the NiFi UI. **Logout** after verifying.

### Step 5: Stop NiFi to Update Config

```powershell
docker-compose stop nifi
```

### Step 6: Copy Config Files from Container to Host

```powershell
# Create backup folder
mkdir nifi-config-backup

# Copy current config files from container to local machine
docker cp nifi:/opt/nifi/nifi-current/conf/login-identity-providers.xml nifi-config-backup/
docker cp nifi:/opt/nifi/nifi-current/conf/authorizers.xml nifi-config-backup/
docker cp nifi:/opt/nifi/nifi-current/conf/nifi.properties nifi-config-backup/
```

### Step 7: Update login-identity-providers.xml

Edit `nifi-config-backup\login-identity-providers.xml`:

Replace the entire `<loginIdentityProviders>` section with:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<loginIdentityProviders>
    <provider>
        <identifier>ldap-provider</identifier>
        <class>org.apache.nifi.ldap.LdapProvider</class>
        <property name="Authentication Strategy">SIMPLE</property>
        
        <property name="Manager DN">cn=admin,dc=nifi,dc=local</property>
        <property name="Manager Password">admin</property>
        
        <property name="Referral Strategy">FOLLOW</property>
        <property name="Connect Timeout">10 secs</property>
        <property name="Read Timeout">10 secs</property>
        
        <property name="Url">ldap://openldap:389</property>
        <property name="User Search Base">ou=users,dc=nifi,dc=local</property>
        <property name="User Search Filter">uid={0}</property>
        
        <property name="Authentication Expiration">12 hours</property>
    </provider>
</loginIdentityProviders>
```

### Step 8: Update authorizers.xml

Edit `nifi-config-backup\authorizers.xml`:

Find the `<userGroupProvider>` section and update it:

```xml
<userGroupProvider>
    <identifier>file-user-group-provider</identifier>
    <class>org.apache.nifi.authorization.FileUserGroupProvider</class>
    <property name="Users File">./conf/users.xml</property>
    <property name="Initial User Identity 1">cn=superAdmin,ou=users,dc=nifi,dc=local</property>
    <property name="Initial User Identity 2">cn=user1,ou=users,dc=nifi,dc=local</property>
    <property name="Initial User Identity 3">cn=user2,ou=users,dc=nifi,dc=local</property>
    <property name="Initial User Identity 4">cn=user3,ou=users,dc=nifi,dc=local</property>
</userGroupProvider>

<accessPolicyProvider>
    <identifier>file-access-policy-provider</identifier>
    <class>org.apache.nifi.authorization.FileAccessPolicyProvider</class>
    <property name="User Group Provider">file-user-group-provider</property>
    <property name="Authorizations File">./conf/authorizations.xml</property>
    <property name="Initial Admin Identity">cn=superAdmin,ou=users,dc=nifi,dc=local</property>
    <property name="Legacy Authorized Users File"></property>
    <property name="Node Identity 1"></property>
    <property name="Node Group"></property>
</accessPolicyProvider>
```

### Step 9: Update nifi.properties

Edit `nifi-config-backup\nifi.properties`:

Find these lines and update them:

```properties
# Change from single-user-provider to ldap-provider
nifi.security.user.login.identity.provider=ldap-provider

# Change from single-user-authorizer to managed-authorizer
nifi.security.user.authorizer=managed-authorizer
```

### Step 10: Copy Updated Files Back to Container

```powershell
# Copy updated files back
docker cp nifi-config-backup/login-identity-providers.xml nifi:/opt/nifi/nifi-current/conf/
docker cp nifi-config-backup/authorizers.xml nifi:/opt/nifi/nifi-current/conf/
docker cp nifi-config-backup/nifi.properties nifi:/opt/nifi/nifi-current/conf/

# Delete the old users/authorizations files so NiFi recreates them
docker exec nifi rm -f /opt/nifi/nifi-current/conf/users.xml
docker exec nifi rm -f /opt/nifi/nifi-current/conf/authorizations.xml
```

### Step 11: Restart NiFi

```powershell
docker-compose start nifi

# Watch logs
docker-compose logs -f nifi
```

Wait for: `Started Server on`

### Step 12: Login with LDAP

Go to: https://localhost:8443/nifi

Login with:
- Username: `superAdmin`
- Password: `password123`

🎉 **Success!** You're now using LDAP authentication!

---

## 🔄 Future Config Changes

Now that you have control, you can edit configs anytime:

```powershell
# 1. Copy file from container
docker cp nifi:/opt/nifi/nifi-current/conf/nifi.properties ./

# 2. Edit locally
notepad nifi.properties

# 3. Copy back
docker cp nifi.properties nifi:/opt/nifi/nifi-current/conf/

# 4. Restart
docker-compose restart nifi
```

---

## 📦 Backup Your Config

```powershell
# Backup entire conf directory
docker cp nifi:/opt/nifi/nifi-current/conf ./nifi-conf-backup

# Restore if needed
docker cp ./nifi-conf-backup/. nifi:/opt/nifi/nifi-current/conf/
docker-compose restart nifi
```

---

## 🐛 Troubleshooting

### Can't login with LDAP users

```powershell
# Check LDAP connection from NiFi
docker exec nifi curl ldap://openldap:389

# Check if users exist in LDAP
docker exec nifi-openldap ldapsearch -x -b "ou=users,dc=nifi,dc=local" -D "cn=admin,dc=nifi,dc=local" -w admin

# Check NiFi logs for auth errors
docker-compose logs nifi | findstr "ldap"
```

### Config changes not taking effect

```powershell
# Fully restart NiFi
docker-compose restart nifi

# Or recreate container (keeps volumes)
docker-compose up -d --force-recreate nifi
```

### Reset everything

```powershell
# Nuclear option - delete all data
docker-compose down -v
docker-compose up -d

# Then start from Step 3
```

---

## ✅ Verification Checklist

- [ ] LDAP container running
- [ ] Users created in LDAP (check phpLDAPadmin at http://localhost:8081)
- [ ] NiFi started successfully
- [ ] Can login with `superAdmin` / `password123`
- [ ] Can login with `user1` / `password123`
- [ ] Create Process Groups and set policies like you did with ZIP version

---

## 🎯 This Approach Gives You:

✅ Full control over config files (just like ZIP)
✅ Can edit configs locally with your favorite editor
✅ Easy to version control (commit config files to git)
✅ Docker benefits (easy deployment, scaling)
✅ Works exactly like the ZIP version you're familiar with
