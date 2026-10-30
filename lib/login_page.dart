import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:placeholder/sign_up_page.dart';

import 'home_page.dart';

class LoginPage extends StatefulWidget {
  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  bool submitLock = false;
  bool obscurePasswordToggle = true;

  String? validateEmail(String? value) {
    String emailRegex =
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+";
    if (value == null || value.isEmpty) {
      return "Please enter your email.";
    }
    if (!RegExp(emailRegex).hasMatch(value)) {
      return "Please enter a valid email.";
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return "Please enter a password.";
    }
    return null;
  }

  void navigateToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (builder) => HomePage()),
    );
  }

  void navigateToSignUpPage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (builder) => SignUpPage()),
    );
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: "Dismiss",
          textColor: Colors.amberAccent,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void onPressedLoginButton() async {
    if (submitLock) return;
    submitLock = true;

    if (formKey.currentState!.validate()) {
      String email = emailController.text;
      String password = passwordController.text;

      try {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        navigateToHomePage();
      } on FirebaseAuthException catch (e) {
        showSnackBar(e.code);
      }
    }

    setState(() {
      submitLock = false;
    });
  }

  Widget loginForm() {
    return Form(
      key: formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextFormField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.email),
              hintText: 'user@website.com',
              labelText: 'Email',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            controller: emailController,
            validator: validateEmail,
          ),
          const SizedBox(height: 20),
          TextFormField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock),
              hintText: 'Password',
              labelText: 'Password',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    obscurePasswordToggle = !obscurePasswordToggle;
                  });
                },
                icon: Icon(
                  obscurePasswordToggle
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
            controller: passwordController,
            validator: validatePassword,
            obscureText: obscurePasswordToggle,
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FilledButton(
                    onPressed: onPressedLoginButton,
                    child: const Text("Login"),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: OutlinedButton(
                    onPressed: navigateToSignUpPage,
                    child: const Text("Sign Up"),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Welcome back",
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Sign in to continue",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 2,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: loginForm(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
