import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_brand.dart';
import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../state/session_provider.dart';
import 'sign_up_screen.dart';

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

  bool _obscure = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints viewport) {
                  // A phone viewport is a finite height. The guard is so this
                  // still lays out rather than asserting if it ever lands in an
                  // unbounded parent.
                  final double minHeight =
                      viewport.maxHeight.isFinite ? viewport.maxHeight : 0.0;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: BwSpacing.xl),
                    // minHeight + IntrinsicHeight is the only combination that
                    // both stretches to the viewport and keeps a Column's flex
                    // children meaningful: ConstrainedBox hands the Column a
                    // minHeight with no max, so a Spacer would resolve to zero on
                    // its own, and IntrinsicHeight is what gives the Column a
                    // bounded height to divide up.
                    //
                    // Two behaviours fall out of it. Where the content is
                    // shorter than the screen, the Spacer takes the slack and
                    // parks the form against the bottom. Where it is taller —
                    // a short device, or a large system font — the column grows
                    // past minHeight, the Spacer collapses to zero, and this
                    // scrolls instead of overflowing.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(
                                top: BwSpacing.lg,
                                bottom: BwSpacing.md,
                              ),
                              child: _Brandmark(),
                            ),

                            // Everything left over between the mark and the
                            // form goes here. That is the whole trick.
                            const Spacer(),

                            const Text(
                              'Welcome back! Sign in to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: BwColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: BwSpacing.lg),

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

                            const SizedBox(height: BwSpacing.lg),

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

                            // --- footer --------------------------------------------
                            //
                            // The last child of the column, so it lands on the bottom of
                            // the viewport whenever the content fits — which is what keeps
                            // it from ever sitting underneath the Log In button or the
                            // Sign Up row above it.
                            const SizedBox(height: BwSpacing.md),
                            const Padding(
                              padding: EdgeInsets.only(bottom: BwSpacing.md),
                              child: Center(
                                child: Text(
                                  'Highlanders Coffee & Tea · Lumban, Laguna',
                                  style: TextStyle(fontSize: 11.5, color: BwColors.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
///
/// Nothing is written under it: the lettering is part of the artwork, so the
/// old "Highlanders" / "Coffee & Tea" text pair was saying the same thing twice,
/// in two different typefaces, at two different sizes.
class _Brandmark extends StatelessWidget {
  const _Brandmark();

  /// Rendered width. Height follows from [BwBrand.aspect], so 180 is140.5 tall.
  ///
  /// Up from 79.4, which held the mark at the same 62px the old black tile
  /// occupied and read as a small icon rather than a header. 180 keeps it clear
  /// of the form on a 360dp screen: the mark is 66% of the gutter-to-gutter
  /// width, leaving the wordmark legible at arm's length over a counter.
  static const double width = 180;

  @override
  Widget build(BuildContext context) {
    // Center, not stretch: the parent Column stretches its children to full
    // width, and an Image with a fixed width would otherwise sit left-aligned.
    return const Center(child: BwBrandmark(width: width));
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
