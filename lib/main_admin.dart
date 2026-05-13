import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'theme/campus_brand.dart';
import 'theme/campus_brand_assets.dart';

/// Separater Einstieg für die technische Admin-Oberfläche (Kunde + Schul-Nutzer anlegen).
///
/// Start: `flutter run -t lib/main_admin.dart -d chrome`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (_) {}
  }
  runApp(const CampusAdminApp());
}

class CampusAdminApp extends StatelessWidget {
  const CampusAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RettBase Campus – Admin',
      debugShowCheckedModeBanner: false,
      theme: CampusBrand.theme(),
      home: const _AdminAuthGate(),
    );
  }
}

/// Einheitlicher Kopf für alle Campus-Admin-Screens (Wordmark + Kontextzeile).
class _CampusAdminAppBarTitle extends StatelessWidget {
  const _CampusAdminAppBarTitle({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CampusBrandAssets.wordmark(height: 44, alignment: Alignment.centerLeft),
        const SizedBox(height: 6),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AdminAuthGate extends StatelessWidget {
  const _AdminAuthGate();

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
        if (snap.data == null) {
          return const _AdminLoginScreen();
        }
        return _CampusAdminHomeScreen(user: snap.data!);
      },
    );
  }
}

class _AdminLoginScreen extends StatefulWidget {
  const _AdminLoginScreen();

  @override
  State<_AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<_AdminLoginScreen> {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 88,
        titleSpacing: 20,
        title: _CampusAdminAppBarTitle(
          subtitle:
              'Anmeldung technischer Admin · Projekt: ${DefaultFirebaseOptions.currentPlatform.projectId}',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nur technische Admins (z. B. admin@rettbase.de in diesem Projekt). '
                  'Konto in der Firebase Console anlegen, falls noch nicht vorhanden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'E-Mail',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Passwort',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Anmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CampusAdminHomeScreen extends StatefulWidget {
  const _CampusAdminHomeScreen({required this.user});

  final User user;

  @override
  State<_CampusAdminHomeScreen> createState() => _CampusAdminHomeScreenState();
}

class _CampusAdminHomeScreenState extends State<_CampusAdminHomeScreen>
    with SingleTickerProviderStateMixin {
  static final _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west1',
  );

  late TabController _tabController;

  final _search = TextEditingController();

  final _newKundenId = TextEditingController();
  final _newSchulName = TextEditingController();
  final _newStrasse = TextEditingController();
  final _newHausnr = TextEditingController();
  final _newPlz = TextEditingController();
  final _newOrt = TextEditingController();
  final _newTelefon = TextEditingController();
  final _newSchulEmail = TextEditingController();
  final _newAdminVorname = TextEditingController();
  final _newAdminNachname = TextEditingController();
  final _newAdminEmail = TextEditingController();
  final _newAdminPasswort = TextEditingController();

  List<Map<String, dynamic>> _kunden = [];
  String? _msg;
  String? _err;
  bool _loadingList = false;
  bool _busyCreate = false;

  @override
  void dispose() {
    _tabController.dispose();
    _search.dispose();
    _newKundenId.dispose();
    _newSchulName.dispose();
    _newStrasse.dispose();
    _newHausnr.dispose();
    _newPlz.dispose();
    _newOrt.dispose();
    _newTelefon.dispose();
    _newSchulEmail.dispose();
    _newAdminVorname.dispose();
    _newAdminNachname.dispose();
    _newAdminEmail.dispose();
    _newAdminPasswort.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _refreshKunden();
  }

  Future<void> _refreshKunden() async {
    setState(() {
      _loadingList = true;
      _err = null;
    });
    try {
      final r = await _functions.httpsCallable('listCampusCustomers').call();
      final data = Map<String, dynamic>.from(r.data as Map? ?? {});
      final raw = data['kunden'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() => _kunden = list);
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _err = '${e.code}: ${e.message}';
        _kunden = [];
      });
    } catch (e) {
      setState(() {
        _err = '$e';
        _kunden = [];
      });
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  String _ortAusKunde(Map<String, dynamic> k) {
    final city = (k['city'] ?? '').toString().trim();
    if (city.isNotEmpty) return city;
    final zc = (k['zipCity'] ?? '').toString().trim();
    if (zc.isEmpty) return '';
    final parts = zc.split(RegExp(r'\s+'));
    if (parts.length <= 1) return zc;
    return parts.sublist(1).join(' ');
  }

  List<Map<String, dynamic>> get _gefilterteKunden {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _kunden;
    return _kunden.where((k) {
      final name = (k['name'] ?? '').toString().toLowerCase();
      final ort = _ortAusKunde(k).toLowerCase();
      final kid = (k['kundenId'] ?? '').toString().toLowerCase();
      return name.contains(q) || ort.contains(q) || kid.contains(q);
    }).toList();
  }

  Future<void> _createCustomerWithAdmin() async {
    setState(() {
      _busyCreate = true;
      _msg = null;
      _err = null;
    });
    try {
      final kid = _newKundenId.text.trim();
      final name = _newSchulName.text.trim();
      if (kid.isEmpty || name.isEmpty) {
        setState(
          () => _err = 'Kunden-ID und Name der Schule sind Pflichtfelder.',
        );
        return;
      }
      final r = await _functions
          .httpsCallable('createCampusCustomerWithAdmin')
          .call({
            'kundenId': kid,
            'name': name,
            'street': _newStrasse.text.trim(),
            'houseNumber': _newHausnr.text.trim(),
            'plz': _newPlz.text.trim(),
            'city': _newOrt.text.trim(),
            'phone': _newTelefon.text.trim(),
            'email': _newSchulEmail.text.trim(),
            'adminVorname': _newAdminVorname.text.trim(),
            'adminNachname': _newAdminNachname.text.trim(),
            'adminEmail': _newAdminEmail.text.trim(),
            'adminPassword': _newAdminPasswort.text,
          });
      final data = Map<String, dynamic>.from(r.data as Map? ?? {});
      setState(() {
        _msg =
            'Kunde und Schul-Admin angelegt: Firestore-ID ${data['docId']}, '
            'Kunden-ID ${data['kundenId']}, Admin-UID ${data['uid']}.';
        _newKundenId.clear();
        _newSchulName.clear();
        _newStrasse.clear();
        _newHausnr.clear();
        _newPlz.clear();
        _newOrt.clear();
        _newTelefon.clear();
        _newSchulEmail.clear();
        _newAdminVorname.clear();
        _newAdminNachname.clear();
        _newAdminEmail.clear();
        _newAdminPasswort.clear();
      });
      await _refreshKunden();
      if (mounted) _tabController.animateTo(1);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busyCreate = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openKunde(Map<String, dynamic> k) async {
    final companyId = (k['id'] ?? '').toString();
    if (companyId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => _CustomerDetailScreen(
          functions: _functions,
          companyId: companyId,
          initial: Map<String, dynamic>.from(k),
          onChanged: _refreshKunden,
        ),
      ),
    );
    if (mounted) await _refreshKunden();
  }

  Widget _bannerFehlerNachricht() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_err != null) ...[
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_err!),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_msg != null) ...[
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_msg!),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildNeuerKundeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bannerFehlerNachricht(),
          Text(
            'Neuer Kunde inkl. erstem Schul-Admin (Rolle „admin“). '
            'Die Kunden-ID wird serverseitig normalisiert (Kleinbuchstaben, Umlaute, Bindestriche).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newKundenId,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'Kunden-ID',
              helperText: 'Buchstaben inkl. äöüß, Ziffern, -, _',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newSchulName,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'Name der Schule',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _newStrasse,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Straße',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _newHausnr,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Haus-Nr.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _newPlz,
                  keyboardType: TextInputType.text,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'PLZ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _newOrt,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Ort',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newTelefon,
            keyboardType: TextInputType.phone,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'Telefonnummer (Schule)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newSchulEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'E-Mail der Schule (Kontakt, optional)',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Schul-Admin (Login)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newAdminVorname,
                  textCapitalization: TextCapitalization.words,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Vorname',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _newAdminNachname,
                  textCapitalization: TextCapitalization.words,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText: 'Nachname',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newAdminEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'E-Mail-Adresse des Admins (Login)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newAdminPasswort,
            obscureText: true,
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'Initiales Passwort (min. 8 Zeichen)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busyCreate ? null : _createCustomerWithAdmin,
            child: _busyCreate
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kunde und Schul-Admin anlegen'),
          ),
        ],
      ),
    );
  }

  Widget _buildBestehendeKundenTab() {
    final filtered = _gefilterteKunden;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: CampusBrand.outlineField(
              context,
              labelText: 'Suche',
              helperText: 'Nach Schulname, Ort oder Kunden-ID',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Leeren',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
            ),
          ),
        ),
        if (_loadingList)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _kunden.isEmpty
                            ? 'Keine Kunden geladen oder Liste leer.'
                            : 'Keine Treffer für die Suche.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final k = filtered[i];
                      final name = (k['name'] ?? '').toString();
                      final ort = _ortAusKunde(k);
                      final kid = (k['kundenId'] ?? '').toString();
                      final active = k['active'] != false;
                      return ListTile(
                        leading: Icon(
                          Icons.school_outlined,
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        title: Text(name.isEmpty ? kid : name),
                        subtitle: Text(
                          [
                            if (ort.isNotEmpty) ort,
                            'Kunden-ID: $kid',
                            if (!active) 'Deaktiviert',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openKunde(k),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 88,
        titleSpacing: 20,
        title: _CampusAdminAppBarTitle(
          subtitle: 'Angemeldet: ${widget.user.email ?? widget.user.uid}',
        ),
        actions: [
          IconButton(
            tooltip: 'Kundenliste neu laden',
            onPressed: _loadingList ? null : _refreshKunden,
            icon: _loadingList
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Abmelden',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.surface,
            elevation: 0,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Neuer Kunde'),
                Tab(text: 'Bestehende Kunden'),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_tabController.index == 1 && _err != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_err!),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildNeuerKundeTab(), _buildBestehendeKundenTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDetailScreen extends StatefulWidget {
  const _CustomerDetailScreen({
    required this.functions,
    required this.companyId,
    required this.initial,
    required this.onChanged,
  });

  final FirebaseFunctions functions;
  final String companyId;
  final Map<String, dynamic> initial;
  final Future<void> Function() onChanged;

  @override
  State<_CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<_CustomerDetailScreen> {
  Map<String, dynamic>? _detail;
  String? _err;
  String? _msg;
  bool _loading = true;
  bool _busyStatus = false;
  bool _busySave = false;

  late final TextEditingController _editName;
  late final TextEditingController _editStrasse;
  late final TextEditingController _editHausnr;
  late final TextEditingController _editPlz;
  late final TextEditingController _editOrt;
  late final TextEditingController _editTelefon;
  late final TextEditingController _editSchulEmail;

  String _formatFunctionsError(FirebaseFunctionsException e) {
    final code = e.code;
    final msg = e.message?.trim() ?? '';
    final useless = code == 'internal' && (msg.isEmpty || msg == 'internal');
    if (useless) {
      return 'Serverfehler ohne Details (Code: internal). '
          'Bitte in der Firebase Console unter Functions prüfen, ob „getCampusCustomer“ '
          'deployed ist und die Logs ansehen.';
    }
    if (msg.isEmpty || msg == code) return code;
    return '$code: $msg';
  }

  @override
  void initState() {
    super.initState();
    _editName = TextEditingController();
    _editStrasse = TextEditingController();
    _editHausnr = TextEditingController();
    _editPlz = TextEditingController();
    _editOrt = TextEditingController();
    _editTelefon = TextEditingController();
    _editSchulEmail = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _editName.dispose();
    _editStrasse.dispose();
    _editHausnr.dispose();
    _editPlz.dispose();
    _editOrt.dispose();
    _editTelefon.dispose();
    _editSchulEmail.dispose();
    super.dispose();
  }

  void _applyDetailToFields(Map<String, dynamic> d) {
    _editName.text = (d['name'] ?? '').toString();
    _editStrasse.text = (d['street'] ?? '').toString();
    _editHausnr.text = (d['houseNumber'] ?? '').toString();
    _editPlz.text = (d['plz'] ?? '').toString();
    _editOrt.text = (d['city'] ?? '').toString();
    _editTelefon.text = (d['phone'] ?? '').toString();
    _editSchulEmail.text = (d['email'] ?? '').toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
      _msg = null;
    });
    try {
      final r = await widget.functions.httpsCallable('getCampusCustomer').call({
        'companyId': widget.companyId,
      });
      _detail = Map<String, dynamic>.from(r.data as Map? ?? {});
    } on FirebaseFunctionsException catch (e) {
      _detail = Map<String, dynamic>.from(widget.initial);
      final initialId = widget.initial['id']?.toString();
      final uselessInternal =
          e.code == 'internal' &&
          (e.message == null ||
              e.message!.trim().isEmpty ||
              e.message!.trim() == 'internal');
      if (uselessInternal &&
          initialId != null &&
          initialId == widget.companyId) {
        _err = null;
      } else {
        _err = _formatFunctionsError(e);
      }
    } catch (e) {
      _err = '$e';
      _detail = Map<String, dynamic>.from(widget.initial);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _applyDetailToFields(_detail ?? widget.initial);
        });
      }
    }
  }

  Future<void> _saveStammdaten() async {
    final name = _editName.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'Name der Schule ist ein Pflichtfeld.');
      return;
    }
    setState(() {
      _busySave = true;
      _err = null;
      _msg = null;
    });
    try {
      await widget.functions.httpsCallable('updateCampusCustomer').call({
        'companyId': widget.companyId,
        'name': name,
        'street': _editStrasse.text.trim(),
        'houseNumber': _editHausnr.text.trim(),
        'plz': _editPlz.text.trim(),
        'city': _editOrt.text.trim(),
        'phone': _editTelefon.text.trim(),
        'email': _editSchulEmail.text.trim(),
      });
      setState(() => _msg = 'Stammdaten gespeichert.');
      await _load();
      await widget.onChanged();
    } on FirebaseFunctionsException catch (e) {
      setState(() => _err = _formatFunctionsError(e));
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busySave = false);
    }
  }

  Future<void> _setActive(bool active) async {
    setState(() {
      _busyStatus = true;
      _err = null;
      _msg = null;
    });
    try {
      await widget.functions.httpsCallable('setCampusCustomerStatus').call({
        'companyId': widget.companyId,
        'active': active,
      });
      await _load();
      await widget.onChanged();
    } on FirebaseFunctionsException catch (e) {
      setState(() => _err = _formatFunctionsError(e));
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busyStatus = false);
    }
  }

  String _t(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final d = _detail ?? widget.initial;
    final active =
        d['active'] != false &&
        (d['status'] ?? 'active').toString().toLowerCase() != 'inactive';
    final headerSubtitle = _t(d['name']).trim().isEmpty
        ? 'Kunde bearbeiten'
        : _t(d['name']).trim();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Zurück',
          onPressed: () => Navigator.of(context).pop(),
        ),
        toolbarHeight: 88,
        titleSpacing: 12,
        title: _CampusAdminAppBarTitle(subtitle: headerSubtitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(_err!),
                        ),
                      ),
                    ),
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(_msg!),
                        ),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('Kunden-Zugang aktiv'),
                    subtitle: Text(
                      active
                          ? 'Nutzer dieses Kunden können sich anmelden und Firestore nutzen.'
                          : 'Deaktiviert: kein Login und kein Datenbankzugriff für Schul-Nutzer '
                                '(technische Superadmins ausgenommen).',
                    ),
                    value: active,
                    onChanged: _busyStatus ? null : (v) => _setActive(v),
                  ),
                  if (_busyStatus)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  const Divider(),
                  _zeile('Kunden-ID', _t(d['kundenId'])),
                  const SizedBox(height: 8),
                  Text(
                    'Stammdaten bearbeiten',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _editName,
                    textCapitalization: TextCapitalization.words,
                    decoration: CampusBrand.outlineField(
                      context,
                      labelText: 'Name der Schule',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _editStrasse,
                          decoration: CampusBrand.outlineField(
                            context,
                            labelText: 'Straße',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _editHausnr,
                          decoration: CampusBrand.outlineField(
                            context,
                            labelText: 'Haus-Nr.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _editPlz,
                          keyboardType: TextInputType.text,
                          decoration: CampusBrand.outlineField(
                            context,
                            labelText: 'PLZ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _editOrt,
                          decoration: CampusBrand.outlineField(
                            context,
                            labelText: 'Ort',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editTelefon,
                    keyboardType: TextInputType.phone,
                    decoration: CampusBrand.outlineField(
                      context,
                      labelText: 'Telefonnummer (Schule)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editSchulEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: CampusBrand.outlineField(
                      context,
                      labelText: 'E-Mail der Schule (Kontakt, optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busySave ? null : _saveStammdaten,
                    child: _busySave
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Stammdaten speichern'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Schul-Admins',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vorname, Nachname und Login-E-Mail anpassen (z. B. neuer Lehrer). '
                    'Passwort separat setzen, falls nötig.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ..._buildSchoolAdminSections(context, d, active),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildSchoolAdminSections(
    BuildContext context,
    Map<String, dynamic> d,
    bool customerActive,
  ) {
    final raw = d['schoolAdmins'];
    if (raw is! List || raw.isEmpty) {
      return [
        Text(
          'Keine Schul-Admins geladen (Rolle admin). Nach Deploy der Functions „getCampusCustomer“ '
          'erneut öffnen oder prüfen, ob ein Admin in „mitarbeiter“ existiert.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    final widgets = <Widget>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final uid = (m['uid'] ?? '').toString();
      if (uid.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _SchoolAdminCard(
            key: ObjectKey(uid),
            functions: widget.functions,
            companyId: widget.companyId,
            uid: uid,
            admin: m,
            customerActive: customerActive,
            onSuccess: (msg) {
              if (!mounted) return;
              setState(() {
                _msg = msg;
                _err = null;
              });
            },
            onError: (err) {
              if (!mounted) return;
              setState(() {
                _err = err;
                _msg = null;
              });
            },
            onReload: () async {
              await _load();
              await widget.onChanged();
            },
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _zeile(String label, String wert) {
    if (wert.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          SelectableText(wert, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Bearbeitung (Name, E‑Mail) und Passwort-Reset für einen Schul-Admin (Rolle admin).
class _SchoolAdminCard extends StatefulWidget {
  const _SchoolAdminCard({
    super.key,
    required this.functions,
    required this.companyId,
    required this.uid,
    required this.admin,
    required this.customerActive,
    required this.onSuccess,
    required this.onError,
    required this.onReload,
  });

  final FirebaseFunctions functions;
  final String companyId;
  final String uid;
  final Map<String, dynamic> admin;
  final bool customerActive;
  final void Function(String msg) onSuccess;
  final void Function(String err) onError;
  final Future<void> Function() onReload;

  @override
  State<_SchoolAdminCard> createState() => _SchoolAdminCardState();
}

class _SchoolAdminCardState extends State<_SchoolAdminCard> {
  late final TextEditingController _vor;
  late final TextEditingController _nach;
  late final TextEditingController _email;
  late final TextEditingController _initialPwIfEmailChange;
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busyProfile = false;
  bool _busyPw = false;
  late String _originalEmail;

  @override
  void initState() {
    super.initState();
    _originalEmail = (widget.admin['email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    _vor = TextEditingController(
      text: (widget.admin['vorname'] ?? '').toString(),
    );
    _nach = TextEditingController(
      text: (widget.admin['nachname'] ?? '').toString(),
    );
    _email = TextEditingController(
      text: (widget.admin['email'] ?? '').toString(),
    );
    _initialPwIfEmailChange = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _SchoolAdminCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admin['email'] != widget.admin['email'] ||
        oldWidget.admin['vorname'] != widget.admin['vorname'] ||
        oldWidget.admin['nachname'] != widget.admin['nachname']) {
      _originalEmail = (widget.admin['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      _vor.text = (widget.admin['vorname'] ?? '').toString();
      _nach.text = (widget.admin['nachname'] ?? '').toString();
      _email.text = (widget.admin['email'] ?? '').toString();
      _initialPwIfEmailChange.clear();
    }
  }

  @override
  void dispose() {
    _vor.dispose();
    _nach.dispose();
    _email.dispose();
    _initialPwIfEmailChange.dispose();
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  bool get _emailChangedFromOriginal =>
      _email.text.trim().toLowerCase() != _originalEmail;

  Future<void> _saveProfile() async {
    final vor = _vor.text.trim();
    final nach = _nach.text.trim();
    final em = _email.text.trim().toLowerCase();
    if (vor.isEmpty || nach.isEmpty) {
      widget.onError('Vorname und Nachname sind Pflichtfelder.');
      return;
    }
    if (!em.contains('@')) {
      widget.onError('Gültige E-Mail-Adresse erforderlich.');
      return;
    }
    if (_emailChangedFromOriginal) {
      final ip = _initialPwIfEmailChange.text;
      if (ip.length < 8) {
        widget.onError(
          'E-Mail wurde geändert: Bitte ein neues Initiales Passwort setzen (mindestens 8 Zeichen).',
        );
        return;
      }
    }
    setState(() => _busyProfile = true);
    try {
      final payload = <String, dynamic>{
        'companyId': widget.companyId,
        'uid': widget.uid,
        'vorname': vor,
        'nachname': nach,
        'email': em,
      };
      if (_emailChangedFromOriginal) {
        payload['newPassword'] = _initialPwIfEmailChange.text;
      }
      await widget.functions
          .httpsCallable('updateCampusSchoolAdminProfile')
          .call(payload);
      if (_emailChangedFromOriginal) {
        _initialPwIfEmailChange.clear();
        widget.onSuccess(
          'Schul-Admin gespeichert. E-Mail geändert – neues Initiales Passwort ist aktiv; bitte der Schule sicher mitteilen.',
        );
      } else {
        widget.onSuccess('Schul-Admin gespeichert (Name).');
      }
      await widget.onReload();
    } on FirebaseFunctionsException catch (e) {
      final m = e.message?.trim() ?? '';
      widget.onError(m.isNotEmpty && m != e.code ? '${e.code}: $m' : e.code);
    } catch (e) {
      widget.onError('$e');
    } finally {
      if (mounted) setState(() => _busyProfile = false);
    }
  }

  Future<void> _submitPw() async {
    final a = _pw1.text;
    final b = _pw2.text;
    if (a.length < 8) {
      widget.onError('Neues Passwort: mindestens 8 Zeichen.');
      return;
    }
    if (a != b) {
      widget.onError('Die beiden Passwort-Eingaben stimmen nicht überein.');
      return;
    }
    setState(() => _busyPw = true);
    try {
      await widget.functions
          .httpsCallable('resetCampusSchoolAdminPassword')
          .call({
            'companyId': widget.companyId,
            'uid': widget.uid,
            'newPassword': a,
          });
      _pw1.clear();
      _pw2.clear();
      widget.onSuccess(
        'Neues Passwort wurde in Firebase Authentication gesetzt.',
      );
    } on FirebaseFunctionsException catch (e) {
      final m = e.message?.trim() ?? '';
      widget.onError(m.isNotEmpty && m != e.code ? '${e.code}: $m' : e.code);
    } catch (e) {
      widget.onError('$e');
    } finally {
      if (mounted) setState(() => _busyPw = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.customerActive;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Schul-Admin', style: Theme.of(context).textTheme.titleSmall),
            if (disabled) ...[
              const SizedBox(height: 8),
              Text(
                'Kunde ist deaktiviert – Bearbeitung und Passwort-Reset sind gesperrt.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vor,
                      textCapitalization: TextCapitalization.words,
                      decoration: CampusBrand.outlineField(
                        context,
                        labelText: 'Vorname',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nach,
                      textCapitalization: TextCapitalization.words,
                      decoration: CampusBrand.outlineField(
                        context,
                        labelText: 'Nachname',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: CampusBrand.outlineField(
                  context,
                  labelText: 'E-Mail (Login)',
                ),
              ),
              if (_emailChangedFromOriginal) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _initialPwIfEmailChange,
                  obscureText: true,
                  decoration: CampusBrand.outlineField(
                    context,
                    labelText:
                        'Neues Initiales Passwort (Pflicht bei E-Mail-Wechsel)',
                    helperText:
                        'Mindestens 8 Zeichen. Der Schul-Admin meldet sich künftig mit der neuen E-Mail und diesem Passwort an.',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busyProfile || _busyPw ? null : _saveProfile,
                child: _busyProfile
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Schul-Admin speichern'),
              ),
              const SizedBox(height: 20),
              Text('Passwort', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _pw1,
                obscureText: true,
                decoration: CampusBrand.outlineField(
                  context,
                  labelText: 'Neues Passwort (min. 8 Zeichen)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: CampusBrand.outlineField(
                  context,
                  labelText: 'Passwort wiederholen',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _busyProfile || _busyPw ? null : _submitPw,
                child: _busyPw
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Neues Passwort setzen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
