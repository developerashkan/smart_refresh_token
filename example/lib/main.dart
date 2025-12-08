import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';
import 'package:dio/dio.dart';
import 'package:smart_refresh_token/src/utils/logger.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Refresh Token Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Dio _dio;
  final List<String> _logs = [];
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _setupDio();
  }

  void _setupDio() {
    // 1. Setup token storage
    final tokenStorage = SecureTokenStorage(
      secureStorage: const FlutterSecureStorage(),
    );

    // 2. Configure retry with dynamic exponential backoff
    final retryConfig = RetryConfig(
      maxRetries: 3,
      baseDelay: const Duration(seconds: 1),
      backoffMultiplier: 2.0,
      jitter: 0.2,
      onRetry: (error, attempt, delay) {
        _addLog('🔄 Retry $attempt after ${delay.inSeconds}s');
      },
    );

    // 3. Configure refresh behavior
    final refreshConfig = RefreshConfig(
      proactiveRefresh: true,
      expirationBuffer: const Duration(minutes: 5),
      onRefreshStart: () => _addLog('🔄 Refreshing token...'),
      onRefreshSuccess: (_) => _addLog('✅ Token refreshed'),
      onRefreshFailure: (e) => _addLog('❌ Refresh failed: $e'),
    );

    // 4. Create interceptor
    final interceptor = RefreshTokenInterceptor(
      tokenStorage: tokenStorage,
      tokenRefresher: _refreshToken,
      onAuthFailure: _handleAuthFailure,
      retryConfig: retryConfig,
      refreshConfig: refreshConfig,
      logger: const RefreshTokenLogger(enabled: true),
    );

    // 5. Setup Dio
    _dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..interceptors.add(interceptor);
  }

  Future<Credentials?> _refreshToken(String refreshToken, Dio client) async {
    try {
      final response = await client.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return Credentials(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          accessTokenExpireAt: DateTime.now().add(const Duration(hours: 1)),
          refreshTokenExpireAt: DateTime.now().add(const Duration(days: 30)),
        );
      }
    } catch (e) {
      _addLog('❌ Refresh error: $e');
    }
    return null;
  }

  Future<void> _handleAuthFailure() async {
    setState(() => _isAuthenticated = false);
    _addLog('🚫 Session expired');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login again')));
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(
        0,
        '[${DateTime.now().toString().substring(11, 19)}] $message',
      );
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  Future<void> _login() async {
    final credentials = Credentials(
      accessToken: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_${DateTime.now().millisecondsSinceEpoch}',
      accessTokenExpireAt: DateTime.now().add(const Duration(seconds: 30)),
      refreshTokenExpireAt: DateTime.now().add(const Duration(days: 7)),
    );

    final storage = SecureTokenStorage(
      secureStorage: const FlutterSecureStorage(),
    );
    await storage.write(credentials);
    setState(() => _isAuthenticated = true);
    _addLog('✅ Login successful');
  }

  Future<void> _makeApiCall() async {
    try {
      final response = await _dio.get('/users/me');
      _addLog('✅ API success: ${response.statusCode}');
    } on DioException catch (e) {
      _addLog('❌ API failed: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Refresh Token'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _isAuthenticated ? Icons.check_circle : Icons.cancel,
                    color: _isAuthenticated ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isAuthenticated ? 'Authenticated' : 'Not Authenticated',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: !_isAuthenticated
                ? ElevatedButton(onPressed: _login, child: const Text('Login'))
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _makeApiCall,
                              child: const Text('API Call'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final storage = SecureTokenStorage(
                                  secureStorage: const FlutterSecureStorage(),
                                );
                                await storage.delete();
                                setState(() => _isAuthenticated = false);
                              },
                              child: const Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // Logs
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.terminal, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Logs',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _logs.isEmpty
                        ? const Center(child: Text('No logs yet'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  _logs[index],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Token Storage Implementation
class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage secureStorage;
  static const _key = 'app_credentials_v1';

  SecureTokenStorage({required this.secureStorage});

  @override
  Future<void> delete() => secureStorage.delete(key: _key);

  @override
  Future<Credentials?> read() async {
    final data = await secureStorage.read(key: _key);
    if (data == null) return null;
    try {
      return Credentials.fromJson(json.decode(data));
    } catch (_) {
      await delete();
      return null;
    }
  }

  @override
  Future<void> write(Credentials credentials) =>
      secureStorage.write(key: _key, value: json.encode(credentials.toJson()));

  @override
  Future<bool> hasCredentials() async {
    final data = await secureStorage.read(key: _key);
    return data != null;
  }
}
