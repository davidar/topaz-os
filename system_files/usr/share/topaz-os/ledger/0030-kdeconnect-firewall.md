---
title: KDE Connect firewall ports stay open for the containerized daemon
date: 2026-08-14
status: active
paths:
  - /etc/firewalld/zones/FedoraWorkstation.xml
---
# KDE Connect firewall ports stay open for the containerized daemon

KDE Connect itself no longer ships in the image (entry 0026 records its
move to the topaz-home companion's distrobox recipe), but its daemon
runs in a container sharing the host network namespace, so phone
discovery and transfers still depend on the host firewall passing
TCP/UDP 1714-1764.

The build opens the `kdeconnect` service (definition shipped by
firewalld itself) in the default `FedoraWorkstation` zone. This is the
single system-side remnant of the former KDE Connect bake (entry 0019):
firewall state is host configuration a per-user recipe cannot durably
own, and an image that silently dropped it would break pairing for
every companion user with no visible cause.
