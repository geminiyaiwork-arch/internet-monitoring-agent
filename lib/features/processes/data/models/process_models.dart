class ProcessInfoDto {
  ProcessInfoDto({
    required this.pid,
    required this.name,
    this.executablePath,
    this.cpuPercent,
    this.memoryMb,
    this.startedAt,
    this.user,
    this.commandLine,
  });

  final int pid;
  final String name;
  final String? executablePath;
  final double? cpuPercent;
  final int? memoryMb;
  final String? startedAt;
  final String? user;
  final String? commandLine;

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'name': name,
        if (executablePath != null) 'exe_path': executablePath,
        if (cpuPercent != null) 'cpu_percent': cpuPercent,
        if (memoryMb != null) 'memory_mb': memoryMb,
        if (startedAt != null) 'started_at': startedAt,
        if (user != null) 'user': user,
        if (commandLine != null) 'cmdline': commandLine,
      };
}
