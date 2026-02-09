import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (AppConfig.orientation == 'portrait') {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else if (AppConfig.orientation == 'landscape') {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  
  runApp(MyApp());
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
      home: WebViewScreen(),
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

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    if (AppConfig.keepAwake) {
      WakelockPlus.enable();
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (!AppConfig.openExternalLinks && 
                !request.url.startsWith(AppConfig.websiteUrl)) {
              _launchURL(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.websiteUrl));

    if (AppConfig.enableZoom) {
      _controller.enableZoom(true);
    }
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
          AppConfig.pullToRefresh
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: WebViewWidget(controller: _controller),
                )
              : WebViewWidget(controller: _controller),
          if (_isLoading)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
