# FreeREAC package repository

The first FreeREAC package repository: signed RPMs of the REAC transport stack
(`libreac`, `libreac-transport`, `reac-pw`) and of `mod-host`, up to the versions
it already carries. It receives no new packages.

New releases of the REAC stack and of the OpenMixer console are published in the
[OpenMixer channel](https://www.openmixer.org). Install its release package and
take `reac-pw` from there:

```bash
sudo dnf install https://www.openmixer.org/rpm/openmixer-release.noarch.rpm
sudo dnf install reac-pw
```

A machine that still has this repository enabled should disable it: `dnf` prefers
the version it finds here when a dependency range points at it, and that version is
older than the channel's.

## What is here

| path | contents |
| --- | --- |
| `rpm/` | the dnf repository: `fedora/<releasever>/<arch>/` + `repodata/` |
| | noarch packages live **inside** each arch directory — `dnf`'s `$basearch` never resolves to a sibling `noarch/` tree |
| `rpm/freereac.repo` | the repo definition (`gpgcheck=1`, `repo_gpgcheck=1`) |
| `rpm/RPM-GPG-KEY-freereac` | the public signing key |

Packages and the repository metadata are both signed. `dnf` verifies each
package against the key above and verifies `repomd.xml` before trusting the
metadata.

## How it was published

The release workflows of `libreac` and `reac-pw` published here until 2026-10-07
(`createrepo_c`, detach-signed metadata). They publish to the OpenMixer channel now.
