import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_button.dart';
import '../../state/session_provider.dart';

/// What the sign-up form hands back to the login screen.
///
/// Returning a result rather than calling the provider directly keeps the
/// login screen as the single owner of the auth flow.
@immutable
class SignUpResult {
  const SignUpResult({
    required this.fullName,
    required this.email,
    required this.password,
    required this.rememberMe,
  });

  final String fullName;
  final String email;
  final String password;
  final bool rememberMe;
}

/// Account creation form. Pops a [SignUpResult]; the caller performs the
/// actual registration so the error surface stays in one place.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.email = '', this.rememberMe = true});

  final String email;
  final bool rememberMe;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController(text: '');
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure = true;
  late bool _rememberMe = widget.rememberMe;

  @override
  void initState() {
    super.initState();
    if (widget.email.trim().isNotEmpty) {
      _email.text = widget.email.trim();
      _email.selection = TextSelection.collapsed(offset: _email.text.length);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      SignUpResult(
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        rememberMe: _rememberMe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = context.watch<SessionProvider>().isBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  BwSpacing.xl,
                  BwSpacing.sm,
                  BwSpacing.xl,
                  BwSpacing.xxl,
                ),
                children: <Widget>[
                  const Text(
                    'Join Highlanders',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: BwColors.text,
                    ),
                  ),
                  const SizedBox(height: BwSpacing.sm),
                  const Text(
                    'Create an account to order for delivery across Lumban and '
                    'track every order in one place.',
                    style: TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
                  ),
                  const SizedBox(height: BwSpacing.xl),

                  TextFormField(
                    controller: _name,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15, color: BwColors.text),
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      hintText: 'Juan Dela Cruz',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
                    ),
                    validator: (String? value) {
                      if ((value ?? '').trim().isEmpty) return 'Enter your name.';
                      return null;
                    },
                  ),
                  const SizedBox(height: BwSpacing.md),

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
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15, color: BwColors.text),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 6 characters',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (String? value) {
                      if ((value ?? '').isEmpty) return 'Choose a password.';
                      if (value!.length < 6) return 'Password must be at least 6 characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: BwSpacing.md),

                  TextFormField(
                    controller: _confirm,
                    enabled: !busy,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 15, color: BwColors.text),
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_reset_rounded, size: 19),
                    ),
                    validator: (String? value) {
                      if (value != _password.text) return 'Passwords do not match.';
                      return null;
                    },
                  ),
                  const SizedBox(height: BwSpacing.lg),

                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: busy ? null : (bool? v) => setState(() => _rememberMe = v ?? false),
                        ),
                      ),
                      const SizedBox(width: BwSpacing.sm),
                      Expanded(
                        child: GestureDetector(
                          onTap: busy ? null : () => setState(() => _rememberMe = !_rememberMe),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            'Keep me signed in',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: busy ? BwColors.disabled : BwColors.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: BwSpacing.lg),

                  BwButton(
                    label: 'Create account',
                    onPressed: busy ? null : _submit,
                    height: 54,
                  ),
                  const SizedBox(height: BwSpacing.md),

                  Center(
                    child: TextButton(
                      onPressed: busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Already have an account? Log in'),
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