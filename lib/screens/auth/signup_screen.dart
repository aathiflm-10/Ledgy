import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/auth_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false;
  
  int _passwordStrength = 0; // 0: Weak, 1: Fair, 2: Good, 3: Strong

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_updatePasswordStrength);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── PASSWORD STRENGTH CALCULATION ──────────────────────────────────
  void _updatePasswordStrength() {
    final pwd = _passwordController.text;
    if (pwd.isEmpty) {
      setState(() => _passwordStrength = 0);
      return;
    }

    int score = 0;
    if (pwd.length >= 8) score++;
    if (pwd.contains(RegExp(r'[0-9]'))) score++;
    if (pwd.contains(RegExp(r'[A-Z]'))) score++;
    if (pwd.contains(RegExp(r'[!@#\$&*~]'))) score++;

    setState(() {
      if (score <= 1) {
        _passwordStrength = 0; // Weak
      } else if (score == 2) {
        _passwordStrength = 1; // Fair
      } else if (score == 3) {
        _passwordStrength = 2; // Good
      } else {
        _passwordStrength = 3; // Strong
      }
    });
  }

  // ── FIREBASE SIGNUP HANDLER ────────────────────────────────────────
  void _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      await ref.read(authServiceProvider).signUp(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      // Router automatically redirects to onboarding
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── GOOGLE SIGN-IN HANDLER ─────────────────────────────────────────
  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String error) {
    String friendlyMessage = 'Sign up failed. Please check details and try again.';
    if (error.contains('email-already-in-use')) {
      friendlyMessage = 'An account already exists with this email address.';
    } else if (error.contains('weak-password')) {
      friendlyMessage = 'The password provided is too weak.';
    } else {
      friendlyMessage = error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyMessage),
        backgroundColor: const Color(0xFFE5524A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── RENDER STRENGTH INDICATOR ──────────────────────────────────────
  Widget _buildStrengthIndicator() {
    final colors = [
      const Color(0xFFE5524A), // Weak - Red
      const Color(0xFFF5A623), // Fair - Orange
      const Color(0xFF3B82F6), // Good - Blue
      const Color(0xFF1DB87A), // Strong - Green
    ];

    final labels = ['Weak', 'Fair', 'Good', 'Strong'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            final active = index <= _passwordStrength && _passwordController.text.isNotEmpty;
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: active ? colors[_passwordStrength] : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        if (_passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Strength: ${labels[_passwordStrength]}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors[_passwordStrength],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                // Small Logo Mark
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB87A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'L',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ledgy',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms),
                const SizedBox(height: 32),

                // Title Heading
                Text(
                  'Create Account',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 150.ms, duration: 500.ms),
                const SizedBox(height: 6),
                Text(
                  'Start your automated tracking journey.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 250.ms, duration: 500.ms),
                const SizedBox(height: 32),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Full name is required';
                    if (value.trim().length < 2) return 'Name is too short';
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    hintText: 'John Doe',
                  ),
                ),
                const SizedBox(height: 16),

                // Email Address
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Email is required';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'name@domain.com',
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    if (value.length < 8) return 'Password must be at least 8 characters';
                    if (!value.contains(RegExp(r'[0-9]'))) return 'Must contain at least 1 number';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Strength bar
                _buildStrengthIndicator(),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 32),

                // Create Account Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Account'),
                  ),
                ),
                const SizedBox(height: 24),

                // Google Sign In
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Sign up with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                const SizedBox(height: 32),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Already have an account? ",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        'Log in',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
