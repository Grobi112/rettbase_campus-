import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme/campus_brand.dart';
import 'theme/campus_brand_assets.dart';

/// Gleiche Schlüssel wie in der RettBase-Haupt-App (`lib/main.dart`, `company_id_screen.dart`).
const String _prefCompanyConfigured = 'rettbase_company_configured';
const String _prefCompanyId = 'rettbase_company_id';
const String _prefSubdomain = 'rettbase_subdomain';
const String _prefLegacyCampusKundenId = 'rettbase_campus_kunden_id';

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
      debugShowCheckedModeBanner: false,
      theme: CampusBrand.theme(),
      home: const _CampusBootstrap(),
    );
  }
}

/// Startlogik wie in der Haupt-App: Prefs → ggf. Kunden-ID → `kundeExists` (parallel zu Auth) → Login / Bereich.
class _CampusBootstrap extends StatefulWidget {
  const _CampusBootstrap();

  @override
  State<_CampusBootstrap> createState() => _CampusBootstrapState();
}

class _CampusBootstrapState extends State<_CampusBootstrap> {
  SharedPreferences? _prefs;
  bool _bootLoading = true;
  String? _companyDocId;
  String? _idScreenHint;
  String? _idScreenInitial;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _migrateLegacyCampusPrefs(SharedPreferences p) async {
    final leg = p.getString(_prefLegacyCampusKundenId)?.trim();
    if (leg == null || leg.isEmpty) return;
    final already = p.getBool(_prefCompanyConfigured) ?? false;
    if (already) {
      await p.remove(_prefLegacyCampusKundenId);
      return;
    }
    await p.setBool(_prefCompanyConfigured, true);
    await p.setString(_prefCompanyId, leg);
    await p.setString(_prefSubdomain, leg);
    await p.remove(_prefLegacyCampusKundenId);
  }

  Future<void> _bootstrap() async {
    final p = await SharedPreferences.getInstance();
    await _migrateLegacyCampusPrefs(p);
    if (!mounted) return;
    setState(() => _prefs = p);

    final configured = p.getBool(_prefCompanyConfigured) ?? false;
    var companyId = p.getString(_prefCompanyId) ?? p.getString(_prefSubdomain) ?? '';
    if (!configured || companyId.isEmpty) {
      if (mounted) {
        setState(() {
          _bootLoading = false;
          _companyDocId = null;
        });
      }
      return;
    }

    final cid = companyId.trim().toLowerCase();
    dynamic kundeRes;
    try {
      kundeRes = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('kundeExists')
          .call({'companyId': cid});
    } catch (e) {
      if (kDebugMode) debugPrint('Campus kundeExists: $e');
      if (mounted) {
        setState(() {
          _bootLoading = false;
          _companyDocId = companyId;
        });
      }
      return;
    }

    if (!mounted) return;

    try {
      final data = (kundeRes as dynamic).data as Map<String, dynamic>?;
      if (data != null) {
        final exists = data['exists'] == true;
        final loginAllowed = data['loginAllowed'] != false;
        final docId = (data['docId'] as String?)?.trim().toLowerCase();
        if (exists && !loginAllowed) {
          setState(() {
            _bootLoading = false;
            _companyDocId = null;
            _idScreenHint =
                'Diese Kunden-ID ist deaktiviert. Bitte wenden Sie sich an den technischen Support.';
            _idScreenInitial = cid;
          });
          return;
        }
        if (exists && docId != null && docId.isNotEmpty && docId != cid) {
          companyId = docId;
          await p.setString(_prefCompanyId, docId);
        } else if (!exists) {
          setState(() {
            _bootLoading = false;
            _companyDocId = null;
            _idScreenHint = 'Diese Kunden-ID wurde nicht gefunden. Bitte erneut eingeben.';
            _idScreenInitial = cid;
          });
          return;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _bootLoading = false;
      _companyDocId = companyId;
    });
  }

  Future<void> _clearCompanyAndSignOut() async {
    await _prefs?.remove(_prefCompanyConfigured);
    await _prefs?.remove(_prefCompanyId);
    await _prefs?.remove(_prefSubdomain);
    await _prefs?.remove(_prefLegacyCampusKundenId);
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    if (mounted) {
      setState(() {
        _companyDocId = null;
        _idScreenHint = null;
        _idScreenInitial = null;
        _bootLoading = false;
      });
    }
  }

  void _onCompanyIdConfigured(String docId) {
    setState(() {
      _companyDocId = docId;
      _idScreenHint = null;
      _idScreenInitial = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null || _bootLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_companyDocId == null) {
      return _KundenIdSetupScreen(
        prefs: _prefs!,
        initialId: _idScreenInitial,
        retryHint: _idScreenHint,
        onConfigured: _onCompanyIdConfigured,
      );
    }
    final cid = _companyDocId!;
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) {
          return _LoginScreen(
            companyId: cid,
            onChangeKundenId: _clearCompanyAndSignOut,
          );
        }
        return _ConnectSelfTestScreen(
          user: user,
          companyId: cid,
          onChangeKundenId: _clearCompanyAndSignOut,
        );
      },
    );
  }
}

class _KundenIdSetupScreen extends StatefulWidget {
  const _KundenIdSetupScreen({
    required this.prefs,
    required this.onConfigured,
    this.initialId,
    this.retryHint,
  });

  final SharedPreferences prefs;
  final ValueChanged<String> onConfigured;
  final String? initialId;
  final String? retryHint;

  @override
  State<_KundenIdSetupScreen> createState() => _KundenIdSetupScreenState();
}

class _KundenIdSetupScreenState extends State<_KundenIdSetupScreen> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialId ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Bitte Kunden-ID eingeben.');
      return;
    }
    final cid = raw.toLowerCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final r = await fn.httpsCallable('kundeExists').call({'companyId': cid});
      final map = Map<String, dynamic>.from(r.data as Map? ?? {});
      final exists = map['exists'] == true;
      final loginAllowed = map['loginAllowed'] != false;
      if (!exists) {
        setState(() {
          _error = 'Diese Kunden-ID existiert nicht. Bitte prüfen Sie die Eingabe.';
        });
        return;
      }
      if (!loginAllowed) {
        setState(() {
          _error = 'Diese Kunden-ID ist deaktiviert. Bitte wenden Sie sich an den technischen Support.';
        });
        return;
      }
      final docIdRaw = map['docId']?.toString().trim();
      final docId = (docIdRaw != null && docIdRaw.isNotEmpty) ? docIdRaw.toLowerCase() : cid;

      await widget.prefs.setBool(_prefCompanyConfigured, true);
      await widget.prefs.setString(_prefCompanyId, docId);
      await widget.prefs.setString(_prefSubdomain, cid);

      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      widget.onConfigured(docId);
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _error = e.code == 'resource-exhausted'
            ? 'Zu viele Anfragen. Bitte später erneut versuchen.'
            : 'Kunde konnte nicht überprüft werden. Bitte prüfen Sie Ihre Verbindung.';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: CampusBrandAssets.wordmark(height: 32),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kunden-ID',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Wie in der RettBase-App: einmalig Kunden-ID, danach Anmeldung mit E-Mail und Passwort.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                if (widget.retryHint != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.retryHint!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Kunden-ID',
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
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Weiter zur Anmeldung'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({
    required this.companyId,
    required this.onChangeKundenId,
  });

  final String companyId;
  final VoidCallback onChangeKundenId;

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
      appBar: AppBar(
        title: CampusBrandAssets.wordmark(height: 30),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onChangeKundenId,
            child: const Text('Kunden-ID ändern'),
          ),
        ],
      ),
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
                const SizedBox(height: 12),
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.apartment_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kunde: ${widget.companyId}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Technische Admin-Oberfläche (Kunden / Nutzer anlegen):',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'flutter run -t lib/main_admin.dart -d chrome',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nach [ensureUsersDoc]: Firestore-Selbsttest unter [campus_connect_selftest/{uid}].
class _ConnectSelfTestScreen extends StatefulWidget {
  const _ConnectSelfTestScreen({
    required this.user,
    required this.companyId,
    required this.onChangeKundenId,
  });

  final User user;
  final String companyId;
  final VoidCallback onChangeKundenId;

  @override
  State<_ConnectSelfTestScreen> createState() => _ConnectSelfTestScreenState();
}

class _ConnectSelfTestScreenState extends State<_ConnectSelfTestScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _status;
  String? _readPayload;
  bool _busy = false;
  bool _ensureBusy = true;
  String? _ensureStatus;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('campus_connect_selftest').doc(widget.user.uid);

  @override
  void initState() {
    super.initState();
    _ensureUsersDoc();
  }

  Future<void> _ensureUsersDoc() async {
    setState(() {
      _ensureBusy = true;
      _ensureStatus = null;
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west1');
      await fn.httpsCallable('ensureUsersDoc').call({'companyId': widget.companyId});
      if (mounted) {
        setState(() {
          _ensureBusy = false;
          _ensureStatus = 'Zuordnung zum Kunden ist aktiv (ensureUsersDoc).';
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _ensureBusy = false;
          _ensureStatus =
              'ensureUsersDoc: ${e.code} – ${e.message}\n'
              'Häufig: noch kein Mitarbeiter-Eintrag mit deiner UID für diese Kunden-ID.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ensureBusy = false;
          _ensureStatus = 'ensureUsersDoc: $e';
        });
      }
    }
  }

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
        'companyId': widget.companyId,
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
        title: CampusBrandAssets.wordmark(height: 30),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _ensureBusy ? null : widget.onChangeKundenId,
            child: const Text('Kunden-ID ändern'),
          ),
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
            const SizedBox(height: 6),
            Text(
              'Kunde: ${widget.companyId}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (_ensureBusy)
              const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Kundenbereich wird eingerichtet…')),
                ],
              )
            else if (_ensureStatus != null) ...[
              Text(_ensureStatus!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Text(
              'Collection: campus_connect_selftest / Doc-ID = deine UID',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Technische Admin-Oberfläche (Kunden / Nutzer):',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      'flutter run -t lib/main_admin.dart -d chrome',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_busy || _ensureBusy) ? null : _runWriteRead,
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
