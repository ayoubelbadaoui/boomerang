import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  static const String routeName = '/signup';

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _birthController = TextEditingController();
  DateTime? _birthday;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _birthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _birthController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Birthday',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                validator: (_) => _birthday == null ? 'Required' : null,
                onTap: () async {
                  final now = DateTime.now();
                  final initial =
                      _birthday ?? DateTime(now.year - 18, now.month, now.day);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(1900, 1, 1),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _birthday = picked;
                      _birthController.text = DateFormat(
                        'yMMMd',
                      ).format(picked);
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (state.loading) const CircularProgressIndicator(),
              if (!state.loading)
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      await ref
                          .read(authControllerProvider.notifier)
                          .signup(
                            _email.text,
                            _password.text,
                            _name.text,
                            _birthController.text,
                          );
                      if (mounted) context.go('/home');
                    }
                  },
                  child: const Text('Create account'),
                ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('I have an account'),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
