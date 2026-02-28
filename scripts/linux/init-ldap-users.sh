#!/bin/bash
# Script to initialize LDAP with users after container starts
# ./scripts/linux/init-ldap-users.sh

echo "Waiting for OpenLDAP to be ready..."
sleep 10

echo "Adding organizational units and users to LDAP..."

# Add the LDIF file to LDAP
docker exec nifi-openldap ldapadd -x -D "cn=admin,dc=nifi,dc=local" -w admin -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init-users.ldif

if [ $? -eq 0 ]; then
    echo "✓ Users successfully added to LDAP"
    echo ""
    echo "Available users:"
    echo "  - superAdmin / password123"
    echo "  - user1 / password123"
    echo "  - user2 / password123"
    echo "  - user3 / password123"
    echo ""
    echo "You can manage users at: http://localhost:8081"
    echo "  Login DN: cn=admin,dc=nifi,dc=local"
    echo "  Password: admin"
else
    echo "✗ Failed to add users. They may already exist."
fi
