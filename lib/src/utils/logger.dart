/// Simple logger for the package
class RefreshTokenLogger {
  final bool enabled;
  final String prefix;

  const RefreshTokenLogger({
    this.enabled = false,
    this.prefix = '[SmartRefreshToken]',
  });

  void log(String message) {
    if (enabled) {
      print('$prefix $message');
    }
  }

  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (enabled) {
      print('$prefix ERROR: $message');
      if (error != null) print('$prefix Error details: $error');
      if (stackTrace != null) print('$prefix Stack trace: $stackTrace');
    }
  }

  void info(String message) {
    if (enabled) {
      print('$prefix INFO: $message');
    }
  }

  void debug(String message) {
    if (enabled) {
      print('$prefix DEBUG: $message');
    }
  }
}
