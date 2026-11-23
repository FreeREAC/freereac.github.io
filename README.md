# FreeREAC package repository

The package repository of FreeREAC, the free implementation of the Roland REAC audio network: signed packages of `libreac`,
`reac-pw` and `reac-stageboxes`. It is the only home of FreeREAC packages and has a signing key of its own.

| tree | contents |
| --- | --- |
| `rpm/fedora/{44,45}/{x86_64,aarch64}/` | the dnf repository (`repodata/` signed) |
| `rpm/fedora/{44,45}/SRPMS/` | the source rpms (`freereac-source`, disabled by default) |
| `deb/debian/{bookworm,trixie}/` | the apt repository, one signed flat index per suite |
| `rpm/RPM-GPG-KEY-freereac`, `deb/freereac.asc` | the one public signing key |
| `import/manifest.txt` | the exact files moved in from the OpenMixer channel |

Install:

```bash
sudo curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-freereac https://freereac.github.io/rpm/RPM-GPG-KEY-freereac
sudo curl -fsSLo /etc/yum.repos.d/freereac.repo https://freereac.github.io/rpm/freereac.repo
sudo dnf install reac-pw
```

Every package and the repository metadata are signed (`gpgcheck=1`, `repo_gpgcheck=1`); the channel keeps the newest 2 versions
of each package. The design, the release path, the way packages are moved in and the order of the prune of the OpenMixer
channel's copies are in [docs/design.md](docs/design.md).
