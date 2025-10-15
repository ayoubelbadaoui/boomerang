import 'package:flutter/material.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const String routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Home Feed (stub)')));
  }
}
