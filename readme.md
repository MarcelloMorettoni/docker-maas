Was tired of installing MAAS all the time for my labs so I just created it in containers
```
docker compose build
docker compose up -d
docker logs -f maas
```

Once the services settle you can reach the UI at [http://localhost:5240/MAAS/](http://localhost:5240/MAAS/) (defaults: `admin`/`admin`).
