import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About ${AppConfig.appName}'),
            subtitle: Text('Version 1.0.0'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacy Policy'),
            trailing: Icon(Icons.open_in_new),
            onTap: () => _launchURL(AppConfig.privacyPolicyUrl),
          ),
          if (AppConfig.termsUrl.isNotEmpty)
            ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('Terms of Service'),
              trailing: Icon(Icons.open_in_new),
              onTap: () => _launchURL(AppConfig.termsUrl),
            ),
        ],
      ),
    );
  }
  
  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
