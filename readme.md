Was tired of installing MAAS all the time for my labs so I just created it in containers
```
docker compose build
docker compose up -d
docker logs -f maas
```

Once the services settle you can reach the UI at [http://localhost:5240/MAAS/](http://localhost:5240/MAAS/) (defaults: `admin`/`admin`).

### Configuration notes

The container now follows the same flow documented in LogicWeb's "How to install MAAS on Ubuntu" guide: during start-up the entrypoint runs `maas init region+rack --maas-url <MAAS_URL> --database-uri <DB_URI>` before handing control to Supervisor. All of the values required by `maas init` are injected via environment variables, so you can tweak the behaviour straight from `docker-compose.yml`:

| Variable | Purpose |
| --- | --- |
| `MAAS_DB_HOST`, `MAAS_DB_PORT`, `MAAS_DB_NAME`, `MAAS_DB_USER`, `MAAS_DB_PASSWORD` | Build the PostgreSQL connection string that is passed to `maas init`. |
| `MAAS_URL` | The URL advertised to the UI/API clients (also used during `maas init`). |
| `MAAS_ADMIN_*` | Credentials fed to `maas createadmin` after the initialization completes. |

Initialization runs only once per persistent `/var/lib/maas` volume. Remove the volume (or delete `/var/lib/maas/.maas-init-done` inside the container) if you need to redo the process with new settings.
