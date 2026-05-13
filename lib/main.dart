import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (_) {}
  }
  runApp(const CampusApp());
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RettBase Campus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF142c52)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Zeigt nach Init entweder Login oder den Firestore-Selbsttest.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return const _LoginScreen();
        }
        return _ConnectSelfTestScreen(user: user);
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RettBase Campus – Anmeldung')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Projekt: ${DefaultFirebaseOptions.currentPlatform.projectId}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Anmelden'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _register,
                  child: const Text('Konto anlegen (Entwicklung)'),
                ),
                const SizedBox(height: 24),
                Text(
                  'In der Firebase Console unter Authentication muss '
                  '„E-Mail/Passwort“ aktiviert sein.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Liest und schreibt genau ein Dokument unter [campus_connect_selftest/{uid}].
class _ConnectSelfTestScreen extends StatefulWidget {
  const _ConnectSelfTestScreen({required this.user});

  final User user;

  @override
  State<_ConnectSelfTestScreen> createState() => _ConnectSelfTestScreenState();
}

class _ConnectSelfTestScreenState extends State<_ConnectSelfTestScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _status;
  String? _readPayload;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('campus_connect_selftest').doc(widget.user.uid);

  Future<void> _runWriteRead() async {
    setState(() {
      _busy = true;
      _status = null;
      _readPayload = null;
    });
    try {
      await _doc.set({
        'ping': DateTime.now().toUtc().toIso8601String(),
        'from': 'rettbase_campus bootstrap',
      }, SetOptions(merge: true));
      final snap = await _doc.get();
      if (!snap.exists) {
        setState(() => _status = 'Dokument fehlt nach Schreiben (unerwartet).');
        return;
      }
      final data = snap.data();
      setState(() {
        _readPayload = data?.toString();
        _status = 'Firestore-Lese/Schreib-Test erfolgreich.';
      });
    } on FirebaseException catch (e) {
      setState(() {
        _status = 'Fehler: ${e.code} – ${e.message}\n'
            'Häufig: Security Rules noch nicht deployed '
            '(siehe rettbase_campus/README).';
      });
      if (kDebugMode) {
        debugPrint('Campus selftest: $e');
      }
    } catch (e) {
      setState(() => _status = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus – Verbindungstest'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Angemeldet als: ${widget.user.email ?? widget.user.uid}'),
            const SizedBox(height: 8),
            Text(
              'Collection: campus_connect_selftest / Doc-ID = deine UID',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _runWriteRead,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: const Text('Firestore testen (Schreiben + Lesen)'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!),
            ],
            if (_readPayload != null) ...[
              const SizedBox(height: 12),
              SelectableText(_readPayload!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
