import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/bw_theme.dart';
import 'features/auth/root_router.dart';
import 'features/shell/app_shell.dart';
import 'services/auth_service.dart';
import 'state/admin_provider.dart';
import 'state/cart_provider.dart';
import 'state/catalog_provider.dart';
import 'state/session_provider.dart';

/// App root.
///
/// Two entry points share one provider graph:
///
///  * [HighlandersApp.new] mounts a single screen directly. Default is the
///    customer tab shell, which is what the screen tests mount.
///  * [HighlandersApp.withRouter] mounts [RootRouter], which starts at the
///    login screen and swaps in the admin or customer panel once a session
///    exists. This is what `main()` runs.
///
/// They differ only in `home`; every provider below is identical, so a test that
/// mounts one screen still exercises the same state layer production uses.
class HighlandersApp extends StatelessWidget {
  const HighlandersApp({super.key, this.home, this.authService, this.roleResolver});

  /// Starts at the login screen and routes by role. Used in production.
  const HighlandersApp.withRouter({super.key, this.authService, this.roleResolver})
      : home = const RootRouter();

  /// Overrides the first screen. Defaults to the tabbed shell; also used for
  /// deep links and for tests that need to mount a single screen.
  final Widget? home;

  /// Injected auth backend. `null` resolves through [AuthServiceFactory], which
  /// picks Firebase or the mock backend depending on configuration.
  final AuthService? authService;
  final RoleResolver? roleResolver;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>(create: (_) => CatalogProvider()),
        ChangeNotifierProvider<SessionProvider>(
          create: (_) => SessionProvider(
            authService: authService,
            roleResolver: roleResolver,
          ),
        ),
        // The shop-wide view: every order, all stock, all staff. Separate from
        // the session because it describes the café, not one customer.
        ChangeNotifierProvider<AdminProvider>(create: (_) => AdminProvider()),
        // The cart needs the catalog to resolve names, prices and the fee
        // schedule, and the session for saved addresses.
        //
        // Note: `update` must read SessionProvider from its own callback
        // context — the enclosing build context sits above the providers.
        ChangeNotifierProxyProvider<CatalogProvider, CartProvider>(
          create: (BuildContext context) => CartProvider(context.read<CatalogProvider>()),
          update: (BuildContext ctx, CatalogProvider catalog, CartProvider? cart) {
            final CartProvider next = cart ?? CartProvider(catalog);
            next.setAddresses(ctx.read<SessionProvider>().addresses);
            return next;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Highlanders Coffee & Tea',
        debugShowCheckedModeBanner: false,
        theme: BwTheme.build(),
        home: home ?? const AppShell(),
      ),
    );
  }
}