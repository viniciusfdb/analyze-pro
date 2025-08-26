import 'package:flutter/material.dart';

class GlobalContext {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get ctx => navigatorKey.currentContext;
}