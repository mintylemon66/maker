import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'home_page.dart';
import 'login_page.dart';

class _AttributedQuote {
  final String quote;
  final String author;
  const _AttributedQuote(this.quote, this.author);
}

/// Quotes for the loading screen, with explicit attribution.
const _loadingQuotes = [
  _AttributedQuote(
    'I hope you live a life you\'re proud of. If you find that you\'re not, I hope you have the strength to start all over again.',
    'F. Scott Fitzgerald, The Curious Case of Benjamin Button',
  ),
  _AttributedQuote(
    'There are all kinds of love in this world but never the same love twice.',
    'F. Scott Fitzgerald',
  ),
  _AttributedQuote(
    'It was only a sunny smile, and little it cost in the giving, but like morning light it scattered the night.',
    'F. Scott Fitzgerald',
  ),
  _AttributedQuote(
    'Life is essentially a cheat and its conditions are those of defeat; the redeeming things are not happiness and pleasure but the deeper satisfactions that come out of struggle.',
    'F. Scott Fitzgerald, The Crack-Up',
  ),
  _AttributedQuote(
    'Vitality shows in not only the ability to persist but the ability to start over.',
    'F. Scott Fitzgerald',
  ),
  _AttributedQuote(
    'I wasn\'t actually in love, but I felt a sort of tender curiosity.',
    'F. Scott Fitzgerald, The Great Gatsby',
  ),
  _AttributedQuote(
    'So we beat on, boats against the current, borne back ceaselessly into the past.',
    'F. Scott Fitzgerald, The Great Gatsby',
  ),
  _AttributedQuote(
    'That is part of the beauty of all literature. You discover that your longings are universal longings.',
    'F. Scott Fitzgerald, The Great Gatsby',
  ),
  _AttributedQuote(
    'To live is the rarest thing in the world. Most people exist, that is all.',
    'Oscar Wilde',
  ),
  _AttributedQuote(
    'Be yourself; everyone else is already taken.',
    'Oscar Wilde',
  ),
  _AttributedQuote(
    'We are all in the gutter, but some of us are looking at the stars.',
    'Oscar Wilde, Lady Windermere\'s Fan',
  ),
  _AttributedQuote(
    'Experience is simply the name we give our mistakes.',
    'Oscar Wilde, The Picture of Dorian Gray',
  ),
  _AttributedQuote(
    'I can resist everything except temptation.',
    'Oscar Wilde, Lady Windermere\'s Fan',
  ),
  _AttributedQuote(
    'There is no such thing as a moral or an immoral book. Books are well written, or badly written.',
    'Oscar Wilde, The Picture of Dorian Gray',
  ),
  _AttributedQuote(
    'It is what you read when you don\'t have to that determines what you will be when you can\'t help it.',
    'Oscar Wilde',
  ),
  _AttributedQuote(
    'I declare after all there is no enjoyment like reading!',
    'Jane Austen, Pride and Prejudice',
  ),
  _AttributedQuote(
    'There is a stubbornness about me that never can bear to be frightened at the will of others. My courage always rises at every attempt to intimidate me.',
    'Jane Austen, Pride and Prejudice',
  ),
  _AttributedQuote(
    'Friendship is certainly the finest balm for the pangs of disappointed love.',
    'Jane Austen, Northanger Abbey',
  ),
  _AttributedQuote(
    'It isn\'t what we say or think that defines us, but what we do.',
    'Jane Austen, Sense and Sensibility',
  ),
  _AttributedQuote(
    'Life seems but a quick succession of busy nothings.',
    'Jane Austen, Mansfield Park',
  ),
  _AttributedQuote(
    'To be fond of dancing was a certain step towards falling in love.',
    'Jane Austen, Pride and Prejudice',
  ),
];

class SplashPage extends StatefulWidget {
  @override
  SplashPageState createState() => SplashPageState();
}

class SplashPageState extends State<SplashPage> {
  late final _AttributedQuote _attributed;

  @override
  void initState() {
    super.initState();
    _attributed = _loadingQuotes[Random().nextInt(_loadingQuotes.length)];
    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .timeout(const Duration(seconds: 2))
            .first;
      } catch (_) {
        // Timed out or no event; fall through to currentUser check.
      }
      user = FirebaseAuth.instance.currentUser;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => user != null ? HomePage() : LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  _attributed.quote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '— ${_attributed.author}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}