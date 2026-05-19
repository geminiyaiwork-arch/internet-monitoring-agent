class InstalledAppDto {
  InstalledAppDto({
    required this.displayName,
    this.displayVersion,
    this.publisher,
    this.installDate,
    this.installPath,
    this.source,
  });

  final String displayName;
  final String? displayVersion;
  final String? publisher;
  final String? installDate;
  final String? installPath;

  /// 'registry' | 'applications' | 'dpkg' | 'rpm' | 'desktop' | 'flatpak'
  final String? source;

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        if (displayVersion != null) 'display_version': displayVersion,
        if (publisher != null) 'publisher': publisher,
        if (installDate != null) 'install_date': installDate,
        if (installPath != null) 'install_path': installPath,
        if (source != null) 'source': source,
      };

  String computeHash() {
    return '${displayName.toLowerCase()}|${displayVersion ?? ''}|${publisher ?? ''}|${installDate ?? ''}';
  }
}
