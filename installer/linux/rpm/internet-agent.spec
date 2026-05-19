Name:           internet-monitoring-agent
Version:        %{?_version}%{!?_version:1.0.0}
Release:        1%{?dist}
Summary:        Internet Monitoring Agent
License:        Proprietary
URL:            https://e-mmtb.uz
BuildArch:      x86_64
Requires:       gtk3, libsecret, libayatana-appindicator3

%description
Authorized education monitoring agent. Collects heartbeat,
internet speed, installed apps and process snapshot for the
central admin panel.

%install
mkdir -p %{buildroot}/opt/internet-monitoring-agent
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
mkdir -p %{buildroot}/usr/lib/systemd/user

cp -r %{_sourcedir}/bundle/* %{buildroot}/opt/internet-monitoring-agent/
install -m 0644 %{_sourcedir}/internet-agent.service \
  %{buildroot}/usr/lib/systemd/user/internet-agent.service

cat > %{buildroot}/usr/share/applications/internet-monitoring-agent.desktop <<EOF
[Desktop Entry]
Name=Internet Monitoring Agent
Comment=Authorized education monitoring agent
Exec=/opt/internet-monitoring-agent/internet
Icon=internet-monitoring-agent
Terminal=false
Type=Application
Categories=Network;Utility;
StartupWMClass=internet
EOF

if [ -f %{_sourcedir}/app_logo.png ]; then
  cp %{_sourcedir}/app_logo.png \
     %{buildroot}/usr/share/icons/hicolor/256x256/apps/internet-monitoring-agent.png
fi

%files
/opt/internet-monitoring-agent
/usr/share/applications/internet-monitoring-agent.desktop
/usr/share/icons/hicolor/256x256/apps/internet-monitoring-agent.png
/usr/lib/systemd/user/internet-agent.service

%post
chmod +x /opt/internet-monitoring-agent/internet || true

%preun
systemctl --user stop internet-agent.service 2>/dev/null || true

%changelog
* Mon Apr 23 2026 E-MMTB <admin@e-mmtb.uz> - 1.0.0-1
- Initial RPM release
