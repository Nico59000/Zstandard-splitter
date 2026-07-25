# Network examples

```sh
# Safe transactional push
zstd-splitter -P -i -R backup@host:/srv/backups archive.tar.zst.part.aaaaaa

# LAN profile with four transfer workers (4.1+)
zstd-splitter -P -i -R backup@host:/srv/backups -O profile=lan -O jobs=4 PART

# Jumbo-frame diagnostics without changing MTU (4.1+)
zstd-splitter -Q network -R backup@host:/srv/backups -O profile=jumbo-lan -O tune=adaptive

# Two destinations, one required (4.2)
zstd-splitter -P -i -R host-a:/backup -R host-b:/backup -O quorum=1 PART

# Inventory and garbage collection (4.2)
zstd-splitter -Q inventory -R host:/backup
zstd-splitter -Q gc -f -R host:/backup -O gc-days=14
```
