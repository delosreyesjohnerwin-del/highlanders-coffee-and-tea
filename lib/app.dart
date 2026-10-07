import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/bw_theme.dart';
import 'data/firestore/repository_factory.dart';
import 'data/firestore/shop_repository.dart';
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
///
/// Stateful rather than stateless for one reason: the [ShopRepository] must
/// exist exactly once for the lifetime of the graph. Held in the `State`, a
/// rebuild reuses it instead of opening a second set of Firestore listeners and
/// orphaning the first.
class HighlandersApp extends StatefulWidget {
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
  State<HighlandersApp> createState() => _HighlandersAppState();
}

class _HighlandersAppState extends State<HighlandersApp> {
  late final ShopRepository _repository = createShopRepository();

  @override
  Widget build(BuildContext context) {
    final ShopRepository repository = _repository;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>(
          create: (_) => CatalogProvider(repository: repository)..bind(),
        ),
        ChangeNotifierProvider<SessionProvider>(
          create: (_) => SessionProvider(
            authService: widget.authService,
            roleResolver: widget.roleResolver,
            repository: repository,
          ),
        ),
        // The shop-wide view: every order, all stock, all staff. Separate from
        // the session because it describes the café, not one customer.
        //
        // Not bound at construction. It binds when the session resolves to an
        // admin — see RootRouter — because a customer reading the order list is
        // denied by the rules and the resulting error would look like a fault.
        ChangeNotifierProvider<AdminProvider>(
          create: (_) => AdminProvider(repository: repository),
        ),
        // The cart needs the catalog to resolve names, prices and the fee
        // schedule, and the session for saved addresses.
        //
        // Listing SessionProvider as a dependency is what forces the sync: when
        // an address is added, edited or deleted in the session, `update` re-runs
        // and the cart's copy of the list follows. Without it, the cart would
        // keep showing an address that was just deleted, or miss a brand-new one.
        ChangeNotifierProxyProvider2<CatalogProvider, SessionProvider, CartProvider>(
          create: (BuildContext context) => CartProvider(context.read<CatalogProvider>()),
          update: (BuildContext ctx, CatalogProvider catalog, SessionProvider session, CartProvider? cart) {
            final CartProvider next = cart ?? CartProvider(catalog);
            next.setAddresses(session.addresses);
            return next;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Highlanders Coffee & Tea',
        debugShowCheckedModeBanner: false,
        theme: BwTheme.build(),
        home: widget.home ?? const AppShell(),
      ),
    );
  }
}