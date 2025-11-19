Was tired of installing MAAS all the time for my labs so I just created it in containers
```
docker compose build
docker compose up -d
docker logs -f maas
```

Once the services settle you can reach the UI at [http://localhost:5240/MAAS/](http://localhost:5240/MAAS/) (defaults: `admin`/`admin`).

The container ships its own Supervisor stack that now also launches a `maas-http` Gunicorn service (implemented here because the upstream package stopped shipping the helper binary). This keeps the API/UI reachable even though `systemd` is not present inside the image and lets you tune the worker pool through `MAAS_HTTP_*` environment variables if you need extra concurrency.

### No Docker? Use Podman (or any OCI runtime)

If Docker/Compose is not available you can run the exact same containers with Podman (or any other OCI compatible runtime). For Podman the workflow looks like this:

```
podman build -t my-maas:3.3 .
podman volume create maas-dbdata
podman volume create maas-data
podman volume create maas-log
podman run -d --name maas-db \
  -e POSTGRES_DB=maasdb \
  -e POSTGRES_USER=maas \
  -e POSTGRES_PASSWORD=maaspass \
  -v maas-dbdata:/var/lib/postgresql/data \
  docker.io/library/postgres:14
podman run -d --name maas --privileged \
  --link maas-db:db \
  -e MAAS_DB_HOST=db \
  -e MAAS_DB_PORT=5432 \
  -e MAAS_DB_NAME=maasdb \
  -e MAAS_DB_USER=maas \
  -e MAAS_DB_PASSWORD=maaspass \
  -e MAAS_URL=http://0.0.0.0:5240/MAAS/ \
  -e MAAS_ADMIN_USERNAME=admin \
  -e MAAS_ADMIN_PASSWORD=admin \
  -e MAAS_ADMIN_EMAIL=admin@example.com \
  -p 5240:80 \
  --tmpfs /run --tmpfs /run/lock \
  -v maas-data:/var/lib/maas \
  -v maas-log:/var/log/maas \
  localhost/my-maas:3.3
podman logs -f maas
```

You can translate the same configuration to `nerdctl compose`, `podman compose`, or Kubernetes manifests if that suits your lab better.

### Temporal workflow runtime

MAAS 3.3 expects a Temporal server for its workflow engine. The container now ships with the official Temporal CLI and launches a
single-node Temporal dev server (backed by SQLite) under Supervisor before `regiond` starts. All data is stored inside the `maas-
data` volume at `/var/lib/maas/temporal`, so you do not lose workflow history across restarts. If you want to inspect the server
directly you can `docker exec` into the MAAS container and run `temporal` CLI commands.

### Configuration notes

The container now follows the same flow documented in LogicWeb's "How to install MAAS on Ubuntu" guide: during start-up the entrypoint runs `maas init` (automatically probing several CLI syntaxes so it works with MAAS 2.9.x through 3.x) with the proper `--maas-url` and database settings before handing control to Supervisor. If Canonical releases a build where the `maas init` CLI no longer exposes database flags, the entrypoint automatically falls back to writing `/etc/maas/regiond.conf` directly from the environment variables, matching the behaviour that worked in the original revisions of this project. All of the values required by `maas init` (or the manual fallback) are injected via environment variables, so you can tweak the behaviour straight from `docker-compose.yml`:

| Variable | Purpose |
| --- | --- |
| `MAAS_DB_HOST`, `MAAS_DB_PORT`, `MAAS_DB_NAME`, `MAAS_DB_USER`, `MAAS_DB_PASSWORD` | Build the PostgreSQL connection string that is passed to `maas init`. |
| `MAAS_URL` | The URL advertised to the UI/API clients (also used during `maas init`). |
| `MAAS_ADMIN_*` | Credentials fed to `maas createadmin` after the initialization completes. |

Initialization runs only once per persistent `/var/lib/maas` volume. Remove the volume (or delete `/var/lib/maas/.maas-init-done` inside the container) if you need to redo the process with new settings.
