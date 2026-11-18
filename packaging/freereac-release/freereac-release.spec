# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
# The package that adds the FreeREAC repository to dnf: a change of baseurl or key reaches every machine as an update of this
# package. Source1 is the public key the channel serves at rpm/RPM-GPG-KEY-freereac, the channel's ONE key (build.sh checks it).
# Version-Release is the release of debian/changelog too: build.sh refuses a build where the two differ.
Name:           freereac-release
Version:        1
Release:        2%{?dist}
Summary:        FreeREAC package repository configuration for dnf
License:        MIT
URL:            https://freereac.github.io
Source0:        freereac.repo
Source1:        RPM-GPG-KEY-freereac
BuildArch:      noarch

%description
Adds the FreeREAC repository, which carries libreac, reac-pw and reac-stageboxes, to dnf, with the key that signs its packages
and metadata. dnf update keeps this configuration current.

%prep

%build

%install
install -Dpm 0644 %{SOURCE0} %{buildroot}%{_sysconfdir}/yum.repos.d/freereac.repo
install -Dpm 0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-freereac

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/freereac.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-freereac

%changelog
* Wed Nov 18 2026 Pau Aliagas <linuxnow@gmail.com> - 1-2
- A freereac-noarch repository beside freereac, as openmixer-noarch is: a noarch package of the channel (this package, a released -devel) is published into the channel's noarch tree, which a dnf client did not read. The one key is unchanged.

* Wed Nov 18 2026 Pau Aliagas <linuxnow@gmail.com> - 1-1
- The FreeREAC repository, ids freereac, and its one key
