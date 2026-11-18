import 'package:flutter_web_auth_2_platform_interface/flutter_web_auth_2_platform_interface.dart';

// The upstream package explicitly supports this opt-out factory.
// https://pub.dev/packages/flutter_web_auth_2#without-the-webview
FlutterWebAuth2Platform? createDesktopWebview() => null;
