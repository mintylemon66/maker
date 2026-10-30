import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_page.dart';
import 'login_page.dart';

class SignUpPage extends StatefulWidget {
  @override
  SignUpPageState createState() => SignUpPageState();
}

class SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  String eulaText = "...";

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();

  bool submitLock = false;
  bool obscurePasswordToggle = true;
  bool obscureConfirmPasswordToggle = true;

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

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return "Please enter a password.";
    } else if (value != passwordController.text) {
      return "Please enter matching passwords.";
    }
    return null;
  }

  void navigateToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (builder) => HomePage()),
    );
  }

  void navigateToLoginPage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (builder) => LoginPage()),
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

  void onPressedSignupButton() async {
    if (submitLock) return;
    submitLock = true;

    if (formKey.currentState!.validate()) {
      await loadEULAText();
      await showEULADialog();
    }

    submitLock = false;
  }

  Future<void> loadEULAText() async {
    eulaText = await rootBundle.loadString('assets/eula.txt');
  }

  Future<void> showEULADialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("End-User License Agreement (EULA)"),
          content: SingleChildScrollView(
            child: ListBody(children: [Text(eulaText)]),
          ),
          actions: [
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop;
              },
            ),
            TextButton(onPressed: signup, child: const Text('Agree')),
          ],
        );
      },
    );
  }

  void signup() async {
    try {
      String email = emailController.text;
      String password = passwordController.text;

      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      navigateToHomePage();
    } on FirebaseAuthException catch (e) {
      if (e.code == "weak-password") {
        showSnackBar("The provided password is too weak.");
      } else if (e.code == 'email-already-in-use') {
        showSnackBar("That email is already in use.");
      } else if (e.code == 'invalidEmail') {
        showSnackBar("The provided email is invalid.");
      } else {
        print(e.code);
        showSnackBar("Unknown Error.");
      }
    }
  }

  Widget signupForm() {
    return Form(
      key: formKey,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Email Field
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
            SizedBox(height: 16),

            // Password Field
            TextFormField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.lock),
                hintText: 'Password',
                labelText: 'Password',
                contentPadding: EdgeInsets.symmetric(
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
            SizedBox(height: 16),

            // Confirm Password Field
            TextFormField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.lock),
                hintText: 'Password',
                labelText: 'Confirm Password',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      obscureConfirmPasswordToggle =
                          !obscureConfirmPasswordToggle;
                    });
                  },
                  icon: Icon(
                    obscureConfirmPasswordToggle
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                ),
              ),
              controller: confirmPasswordController,
              validator: validateConfirmPassword,
              obscureText: obscureConfirmPasswordToggle,
            ),

            SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: FilledButton(
                      onPressed: onPressedSignupButton,
                      child: const Text("Sign Up"),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: OutlinedButton(
                      onPressed: navigateToLoginPage,
                      child: const Text("Login"),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
                "Create account",
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Sign up to get started",
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
                    child: signupForm(),
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
