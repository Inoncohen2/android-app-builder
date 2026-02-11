import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _setOrientation(AppConfig.orientation);
  runApp(MyApp());
}

void _setOrientation(String orientation) {
  if (orientation == 'portrait') {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else if (orientation == 'landscape') {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _getThemeMode(),
      home: AppConfig.splashScreen ? SplashScreen() : WebViewScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final primaryColor = _parseColor(AppConfig.primaryColor);
    return ThemeData(
      brightness: brightness,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  ThemeMode _getThemeMode() {
    switch (AppConfig.themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => WebViewScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _parseColor(AppConfig.primaryColor);
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.web, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text(
              AppConfig.appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }
}

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (AppConfig.keepAwake) {
      WakelockPlus.enable();
    }
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36'
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            print('🌐 Loading: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (url) {
            print('✅ Loaded: $url');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            print('❌ Error: ${error.description}');
            if (error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.connect ||
                error.errorType == WebResourceErrorType.timeout) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  _errorMessage = 'Failed to load website. Check your connection.';
                });
              }
            }
          },
          onHttpError: (error) {
            print('❌ HTTP ${error.response?.statusCode}');
          },
          onNavigationRequest: (request) {
            print('📍 Navigating to: ${request.url}');
            
            final requestUri = Uri.parse(request.url);
            final baseUri = Uri.parse(AppConfig.websiteUrl);
            
            if (requestUri.host == baseUri.host || 
                requestUri.host.endsWith('.${baseUri.host}')) {
              return NavigationDecision.navigate;
            }
            
            if (AppConfig.openExternalLinks) {
              return NavigationDecision.navigate;
            } else {
              _launchURL(request.url);
              return NavigationDecision.prevent;
            }
          },
        ),
      );

    if (AppConfig.enableZoom) {
      _controller.enableZoom(true);
    } else {
      _controller.enableZoom(false);
    }

    _controller.loadRequest(
      Uri.parse(AppConfig.websiteUrl),
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );
  }

  @override
  void dispose() {
    if (AppConfig.keepAwake) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _refresh() async {
    await _controller.reload();
  }

  Color _parseColor(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppConfig.showNavigation
          ? AppBar(
              title: Text(AppConfig.appName),
              actions: [
                IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          if (_hasError)
            _buildErrorView()
          else
            _buildWebView(),
          if (_isLoading && !_hasError)
            _buildLoadingIndicator(),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (AppConfig.pullToRefresh) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: _parseColor(AppConfig.primaryColor),
        child: WebViewWidget(controller: _controller),
      );
    } else {
      return WebViewWidget(controller: _controller);
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(
            'Oops! Something went wrong',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          SizedBox(height: 8),
          Text(
            AppConfig.websiteUrl,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _isLoading = true;
              });
              _controller.reload();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _parseColor(AppConfig.primaryColor),
            ),
            child: Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              _parseColor(AppConfig.primaryColor),
            ),
          ),
          SizedBox(height: 16),
          Text('Loading...'),
        ],
      ),
    );
  }
}
