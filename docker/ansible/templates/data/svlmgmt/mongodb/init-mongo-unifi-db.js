db.getSiblingDB("unifi").createUser({user: "unifi", pwd: "{{ apps__unifi_db_password }}", roles: [{role: "dbOwner", db: "MONGO_DBNAME"}]});
db.getSiblingDB("unifi_stat").createUser({user: "unifi", pwd: "{{ apps__unifi_db_password }}", roles: [{role: "dbOwner", db: "MONGO_DBNAME_stat"}]});
