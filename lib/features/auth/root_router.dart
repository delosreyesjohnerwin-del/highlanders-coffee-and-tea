import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_provider.dart';
import '../../state/session_provider.dart';
import '../admin/admin_dashboard_screen.dart';
import '../shell/app_shell.dart';
import 'login_screen.dart';

/// The app's root. Decides which panel a signed-in user sees.
///
/// This is the whole role-separation mechanism in one place: nobody navigates
/// between the two panels by hand, the session decides. An admin can never land
/// in the customer tabs and vice versa, because the destination is a pure
/// function of `isAdmin`.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  /// Identity of the account last routed to, so [ShellNav] resets exactly once
  /// per sign-in rather than on every rebuild.
  String? _routedFor;

  void _syncNavAfterAuthChange(String signature) {
    if (_routedFor == signature) return;
    _routedFor = signature;

    // ShellNav is process-global. A second sign-in would otherwise inherit the
    // previous user's tab, so drop back to Home. Deferred to after the frame
    // because writing to the notifier mid-build would mark the tree dirty.
    WidgetsBinding.instance.addPostFrameCallback((_) => ShellNav.reset());
  }

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();

    if (!session.isSignedIn) {
      _routedFor = null;
      return const LoginScreen();
    }

    _syncNavAfterAuthChange('${session.user.uid}:${session.user.role.name}');

    if (session.isAdmin) {
      // Bind here, not in the provider's constructor. The order list and staff
      // roster are admin-only in the rules, so subscribing while signed out or as
      // a customer would produce a PERMISSION_DENIED the operator cannot act on.
      // Binding on the admin route means the read only happens where it is legal.
      //
      // Idempotent, so a rebuild is free.
      context.read<AdminProvider>().bind();
      return const AdminDashboardScreen();
    }

    return const AppShell();
  }
}