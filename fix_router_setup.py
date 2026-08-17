# -*- coding: utf-8 -*-
import codecs

path = 'lib/core/navigation/app_router.dart'
with codecs.open(path, 'r', 'utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_redirect = """    redirect: (context, state) async {
      final isLoggedIn = authState != null;
      final isLoginRoute = state.matchedLocation.startsWith('/login');
      final isSetupRoute = state.matchedLocation.startsWith('/setup');

      if (isSetupRoute) return null;
      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/dashboard';
      return null;
    },"""

new_redirect = """    redirect: (context, state) async {
      final isLoggedIn = authState != null;
      final isLoginRoute = state.matchedLocation.startsWith('/login');
      final isSetupRoute = state.matchedLocation.startsWith('/setup');
      
      // If database is not connected (no config found or connect failed), force setup
      final isDbConnected = DbConnection.instance.isConnected;
      if (!isDbConnected && !isSetupRoute) return '/setup';

      if (isSetupRoute) return null;
      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/dashboard';
      return null;
    },"""

text = text.replace(old_redirect, new_redirect)

if "import '../../core/database/db_connection.dart';" not in text:
    text = text.replace("import 'package:go_router/go_router.dart';", "import 'package:go_router/go_router.dart';\nimport '../../core/database/db_connection.dart';")

with codecs.open(path, 'w', 'utf-8') as f:
    f.write(text)
