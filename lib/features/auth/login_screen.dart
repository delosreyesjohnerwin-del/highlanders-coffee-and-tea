import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_brand.dart';
import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../core/widgets/bw_segment.dart';
import '../../data/models/order.dart';
import '../../services/mock_auth_service.dart';
import '../../state/session_provider.dart';
import 'sign_up_screen.dart';

/// Which role the user is signing in as.
///
/// On the real Firebase backend this is ignored — the role comes from
/// `users/{uid}`. It exists so the admin and customer panels can be exercised
/// without two provisioned accounts.
enum LoginRole {
  customer('Customer', Icons.person_outline_rounded),
  admin('Admin', Icons.admin_panel_settings_outlined);

  const LoginRole(this.label, this.icon);

  final String label;
  final IconData icon;

  UserRole get asUserRole => this == LoginRole.admin ? UserRole.admin : UserRole.customer;
}

/// Monochrome login screen.
///
/// Google sign-in is the primary path; the email/password form sits beneath it
/// as the fallback. Both routes converge on [SessionProvider], which is what
/// decides which panel opens.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  LoginRole _role = LoginRole.customer;
  bool _obscure = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Swaps the role and pre-fills the matching demo address, so the admin
  /// panel can be reached in two taps instead of by typing.
  void _setRole(LoginRole role) {
    setState(() => _role = role);

    final String demo = MockAuthService.demoIdentityFor(role.asUserRole).email;
    if (_email.text.trim() != demo) {
      _email.text = demo;
      _email.selection = TextSelection.collapsed(offset: demo.length);
    }
  }

  void _toggleObscure() => setState(() => _obscure = !_obscure);

  Future<void> _submitGoogle() async {
    final SessionProvider session = context.read<SessionProvider>();
    final bool ok = await session.signInWithGoogle();

    if (!mounted || ok) return;

    // A cancelled account chooser surfaces as a null error and is not worth a
    // message; anything else is.
    final String? error = session.lastError;
    if (error != null && error.isNotEmpty) _showError(error);
  }

  Future<void> _submitPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final SessionProvider session = context.read<SessionProvider>();
    final bool ok = await session.signInWithPassword(
      email: _email.text,
      password: _password.text,
      rememberMe: _rememberMe,
    );

    if (!mounted || ok) return;
    final String? error = session.lastError;
    if (error != null && error.isNotEmpty) _showError(error);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSignUp() async {
    final SessionProvider session = context.read<SessionProvider>();
    final SignUpResult? result = await Navigator.of(context).push<SignUpResult>(
      MaterialPageRoute<SignUpResult>(
        builder: (_) => SignUpScreen(email: _email.text, rememberMe: _rememberMe),
      ),
    );

    if (!mounted || result == null) return;

    final bool ok = await session.register(
      fullName: result.fullName,
      email: result.email,
      password: result.password,
      rememberMe: result.rememberMe,
    );

    if (!mounted || ok) return;
    final String? error = session.lastError;
    if (error != null && error.isNotEmpty) _showError(error);
  }

  void _forgotPassword() {
    final TextEditingController controller = TextEditingController(text: _email.text.trim());

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: BwColors.surface,
        surfaceTintColor: BwColors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BwRadius.card),
          side: const BorderSide(color: BwColors.border),
        ),
        title: const Text(
          'Reset password',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'We will email you a link to choose a new password.',
              style: TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
            ),
            const SizedBox(height: BwSpacing.lg),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontSize: 15, color: BwColors.text),
              decoration: const InputDecoration(hintText: 'Email address'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showError('Password reset is not wired up yet.');
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();
    final bool busy = session.isBusy;
    final String backendNote = session.authService.unavailableReason;

    return Scaffold(
      backgroundColor: BwColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Keeps the form readable on tablets without letting it stretch
            // edge to edge on a phone.
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  BwSpacing.xl,
                  BwSpacing.xl,
                  BwSpacing.xl,
                  BwSpacing.xxl,
                ),
                children: <Widget>[
                  const _Brandmark(),
                  const SizedBox(height: BwSpacing.xl),

                  const Text(
                    'Welcome back! Select a role or sign in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.45, color: BwColors.textMuted),
                  ),
                  const SizedBox(height: BwSpacing.xxl),

                  // --- role switcher -------------------------------------
                  const Text(
                    'SIGN IN AS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: BwColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: BwSpacing.sm),
                  BwSegmented<LoginRole>(
                    segments: LoginRole.values,
                    selected: _role,
                    onChanged: busy ? (_) {} : _setRole,
                    labelBuilder: (LoginRole r) => r.label,
                  ),
                  const SizedBox(height: BwSpacing.xxl),

                  // --- primary action ------------------------------------
                  BwButton(
                    label: 'Continue with Google',
                    icon: Icons.g_mobiledata_rounded,
                    onPressed: busy ? null : _submitGoogle,
                    height: 54,
                  ),
                  const SizedBox(height: BwSpacing.md),
                  const _OrDivider(),
                  const SizedBox(height: BwSpacing.xl),

                  // --- credentials --------------------------------------
                  TextFormField(
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    style: const TextStyle(fontSize: 15, color: BwColors.text),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@email.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                    ),
                    validator: (String? value) {
                      final String v = (value ?? '').trim();
                      if (v.isEmpty) return 'Enter your email address.';
                      if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(v)) {
                        return 'That email address looks invalid.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: BwSpacing.md),
                  TextFormField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 15, color: BwColors.text),
                    onFieldSubmitted: (_) => busy ? null : _submitPassword(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 6 characters',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                      suffixIcon: IconButton(
                        onPressed: _toggleObscure,
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (String? value) {
                      if ((value ?? '').isEmpty) return 'Enter your password.';
                      if (value!.length < 6) return 'Password must be at least 6 characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: BwSpacing.md),

                  // --- remember me + forgot -------------------------------
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: busy
                              ? null
                              : (bool? v) => setState(() => _rememberMe = v ?? false),
                        ),
                      ),
                      const SizedBox(width: BwSpacing.sm),
                      Expanded(
                        child: GestureDetector(
                          onTap: busy
                              ? null
                              : () => setState(() => _rememberMe = !_rememberMe),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: busy ? BwColors.disabled : BwColors.text,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: BwSpacing.lg),

                  BwButton(
                    label: 'Log In',
                    onPressed: busy ? null : _submitPassword,
                    height: 54,
                  ),

                  if (busy) ...<Widget>[
                    const SizedBox(height: BwSpacing.lg),
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],

                  const SizedBox(height: BwSpacing.xl),

                  // --- footer --------------------------------------------
                  //
                  // A Wrap, not a Row: the prompt plus the button is the
                  // widest line on this screen, and a fixed-width test font
                  // renders "Don't have an account?" at ~300px on its own.
                  // Wrapping keeps both readable at 320dp and lets the button
                  // drop to its own line when space is tight.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: BwSpacing.xs,
                    children: <Widget>[
                      Text(
                        "Don't have an account?",
                        style: TextStyle(
                          fontSize: 13.5,
                          color: busy ? BwColors.disabled : BwColors.textMuted,
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : _openSignUp,
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                  const SizedBox(height: BwSpacing.sm),

                  if (backendNote.isNotEmpty) _BackendNote(message: backendNote),

                  const SizedBox(height: BwSpacing.lg),
                  const Center(
                    child: Text(
                      'Highlanders Coffee & Tea · Lumban, Laguna',
                      style: TextStyle(fontSize: 11.5, color: BwColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand mark, sitting directly on the page.
///
/// Deliberately not sitting in a tile. The mark is a dark green wordmark on a
/// transparent ground, so the previous black rounded square would have put it at
/// roughly 1.9:1 contrast. Straight onto the white page it reads at about 11:1
/// and matches the launcher icon exactly.
class _Brandmark extends StatelessWidget {
  const _Brandmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // Width is derived to hold the mark at the same 62px height the old
        // black tile occupied (62 * 610/476 = 79.4). Growing the header pushed the
        // sign-up row out of the ListView's lazily-built viewport at 360dp,
        // which silently dropped it from the layout test.
        const BwBrandmark(width: 79.4),
        const SizedBox(height: BwSpacing.lg),
        const Text(
          'Highlanders',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: BwColors.text,
          ),
        ),
        const Text(
          'Coffee & Tea',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4,
            color: BwColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Hairline rule with a centred "or".
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md),
          child: Text(
            'or',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BwColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
        ),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

/// Surfaces which auth backend is live so a dormant Google button is never a
/// mystery during development.
class _BackendNote extends StatelessWidget {
  const _BackendNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md, vertical: BwSpacing.md),
      color: BwColors.subtle,
      borderColor: BwColors.border,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: BwColors.textMuted),
          const SizedBox(width: BwSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: BwColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}