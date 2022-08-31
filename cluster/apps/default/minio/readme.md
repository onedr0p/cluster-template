# Notes

## CLI access

Once the console is up, you can connect to it with the minio console:

```sh

# start a container with the  cli
docker run -it --entrypoint=/bin/sh minio/mc
Unable to find image 'minio/mc:latest' locally
latest: Pulling from minio/mc
a96e4e55e78a: Pull complete
67d8ef478732: Pull complete
8c1d22ef296f: Pull complete
9572033e5fbb: Pull complete
a709e061bbfd: Pull complete
Digest: sha256:8fdaacaec6655ef5cc15210fa74900f2d46931484ead5215612ad9092e472123
Status: Downloaded newer image for minio/mc:latest
sh-4.4#
# note the console changed, as we are in the container ^^

# connect to the minio instance
sh-4.4# mc alias set minio https://s3.<! your domain!> minio-admin <!your secret key!>
Added `minio` successfully.
sh-4.4#
sh-4.4#

```

After this we can interact with Mino, for example list / create / remove users

```sh

sh-4.4# mc admin user list minio
enabled    velero                readwrite,diagnos...
enabled    thanos                readwrite
sh-4.4# mc admin user add minio testuser password123!
Added user `testuser` successfully.
sh-4.4# mc admin user list minio
enabled    testuser
enabled    thanos                readwrite
enabled    velero                readwrite,diagnos...
sh-4.4# mc admin user remove minio testuser
Removed user `testuser` successfully.
sh-4.4# mc admin user list minio
enabled    thanos                readwrite
enabled    velero                readwrite,diagnos...
sh-4.4#

```

refernce:

- <https://www.stackhero.io/en/services/MinIO/documentations/Getting-started/Use-the-MinIO-CLI>

- <https://hub.docker.com/r/minio/mc/>
