# cl-pg-cluster
Postgres database 9.6 on Centos 7.3 with streaming replication. The postgres image will contain a ssh server, repmgr and supervisord (there is a variant with systemd)

There is one pgpool; it works also with two pgpool in watch dog mode but since this set-up is targeted at a docker swarm cluster the normal case will be one pgpool container running which will be failed-over by swarm when needed.

There is a manager application, written in nodejs (the front-end is written in react). this small web application on top of pgpool let visualize the cluster state and will to allow fail-over, switch-over, etc. this is completly WIP for now. The backend will be nodejs with websocket and the front-end React+Redux. I will also make an electron app. 

What's worth mentioning that is specific to docker is that everytime the container is started (postgres container or pgpool container), it is configured again based on the environment variables (i.e. /etc/repmgr/9.6/repmgr.conf and /etc/pgpool-II/pgpool.conf are rebuild, among others). Similarly the file /etc/pgpool-II/pool_passwd is rebuild again, by querying the postgres database).

There are various instances of docker-compose files, to test various test cases. docker-compose files are convenient to set all env variables.

** this is WIP: the end result will be 1 master, 2 slaves (with repmgr) and 2 pgpool **

I don't have time to work on it now. However in the coming months I will have to do it for work and so will get time...

## build

see the script build.sh, it build the image postgres (pg) and the image pgpool and the manager image (the manager image contains both the server and the client app).

## run 

It is easy to start the containers with docker compose. For production one will need to use docker in swarm mode but to test on a single machine docker compose is perfect.

```
docker-compose up
```

The entrypoint of the docker image is entrypoint.sh. This script calls initdb.sh (directory bootstrap). initdb.sh tests if the file $PGDATA/postgresql.conf exists, and if not it creates the database with the users corresponding to MSLIST. For each micro-service in the list, a _owner and _user user are created. passwords can be given via MSOWNERPWDLIST and MSUSERPWDLIST

## develop

To develop the manager application, one should first run pg01, pg02 and pgpool01 via a docker-compose (remove the manager from docker-compose.yml).

Then start a nodejs container linked to the network of the compose above and with the sources host mounted, for example on my set-up

```
docker run -ti --network=pgcluster_default -v /Users/pierre/git/pgcluster/manager:/sources -p 8080:8080 manager:0.3.0 /bin/bash 
```
once in the container

```
cd /sources/server
npm start
```

after that start the client application (react application build using create-react-app)

```
cd /Users/pierre/git/pgcluster/manager/client
npm start
```



### get inside the container

you can exec a shell in the container to look around

```
docker exec -ti pgpool01 /bin/bash
```
you can also ssh into the container

## run pgpool

When the container starts the configuration /etc/pgpool-II/pgpool.conf is build based on environment variables passed in the run command.

The following environment variables are important to properly set-up pgpool


* PGMASTER_NODE_NAME: pg01. Node name of the postgres database. Needed so that the container can query the list of users and build the pool_passwd list
* PG_BACKEND_NODE_LIST: 0:pg01:9999:1:/u01/pg96/data:ALLOW_TO_FAILOVER, 1:pg02, etc.
                # csv list of backend postgres databases, each backend db contains (separated by :)
                # number (start with 0):host name:pgpool port (default 9999):data dir (default /u01/pg96/data):flag ALLOW_TO_FAILOVER or DISALLOW_TO_FAILOVER
                # not needed when there is a single postgres DB
* PGP_NODE_NAME: pgpool01
* REPMGRPWD: repmgr_pwd (must correspond to the value in postgres of course)
* DELEGATE_IP: 172.18.0.100 Only if you want the watchdog mode. Note that this watchdog mode does not make a lot of sense inside docker, it is probably better to use the HA functionality of docker swarm
* TRUSTED_SERVERS: 172.23.1.250 When using the watchdog, it helps prevent split-brain
* PGP_HEARTBEATS: "0:pgpool01:9694,1:pgpool02:9694" When using the watchdog
* PGP_OTHERS: "0:pgpool02:9999" The other pgpool nodes, needed for the configuration


## users and passords

* the users are created via the script initdb.sh, have a look at it.
* postgres unix user has uid 50010
