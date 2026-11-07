import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'data.dart';
import 'screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? failure;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (const bool.fromEnvironment('USE_EMULATORS')) {
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '10.0.2.2',
      );
      await auth.useAuthEmulator(host, 9099);
      db.useFirestoreEmulator(host, 8080);
      db.settings = const Settings(persistenceEnabled: false);
    } else if (auth.currentUser != null) {
      try {
        await auth.currentUser!.reload();
      } on FirebaseAuthException catch (e) {
        if ([
          'user-not-found',
          'invalid-user-token',
          'user-token-expired',
          'invalid-credential',
        ].contains(e.code)) {
          await auth.signOut();
        }
      }
    }
  } catch (e) {
    failure = e;
  }
  runApp(YukKasirApp(failure: failure));
}

class YukKasirApp extends StatelessWidget {
  const YukKasirApp({super.key, this.failure});
  final Object? failure;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Yuk Kasir Laundry',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff24649a)),
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xff183c58),
      ),
    ),
    home: failure != null
        ? Scaffold(body: Center(child: Text('Firebase belum siap.\n$failure')))
        : StreamBuilder<User?>(
            stream: auth.authStateChanges(),
            builder: (c, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (s.data == null) return const LoginPage();
              return StreamBuilder(
                stream: db.collection('users').doc(s.data!.uid).snapshots(),
                builder: (c, p) {
                  if (p.hasError) {
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('Akun'),
                        actions: [
                          TextButton(
                            onPressed: () => auth.signOut(),
                            child: const Text('Masuk ulang'),
                          ),
                        ],
                      ),
                      body: Center(child: Text(errorText(p.error!))),
                    );
                  }
                  if (!p.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!p.data!.exists) return const ProfileSetup();
                  return HomeShell(profile: p.data!.data()!);
                },
              );
            },
          ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit(bool google) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (google) {
        await GoogleSignIn.instance.initialize();
        final account = await GoogleSignIn.instance.authenticate();
        await auth.signInWithCredential(
          GoogleAuthProvider.credential(
            idToken: account.authentication.idToken,
          ),
        );
      } else if (register) {
        final result = await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
        await result.user!.sendEmailVerification();
      } else {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'asset/Centered Yuk Kasir logo on white.png',
                  height: 160,
                  fit: BoxFit.contain,
                  semanticLabel: 'Logo Yuk Kasir',
                ),
                const SizedBox(height: 20),
                Text(
                  'Yuk Kasir Laundry',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.headlineLarge,
                ),
                const Text(
                  'Kelola laundry, lebih mudah.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                Text(
                  register ? 'Buat akun baru' : 'Selamat datang kembali',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Kata sandi'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : () => submit(false),
                  child: Text(
                    busy
                        ? 'Memproses…'
                        : register
                        ? 'Daftar'
                        : 'Masuk',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => submit(true),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Lanjutkan dengan Google'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => register = !register),
                  child: Text(
                    register
                        ? 'Sudah punya akun? Masuk'
                        : 'Belum punya akun? Daftar',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            await auth.sendPasswordResetEmail(
                              email: email.text.trim(),
                            );
                            if (c.mounted) {
                              message(
                                c,
                                'Email pemulihan dikirim jika akun terdaftar.',
                              );
                            }
                          } catch (e) {
                            if (c.mounted) message(c, errorText(e));
                          }
                        },
                  child: const Text('Lupa kata sandi?'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfileSetup extends StatefulWidget {
  const ProfileSetup({super.key});
  @override
  State<ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetup> {
  final name = TextEditingController(), phone = TextEditingController();
  String role = 'Owner';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Lengkapi akun'),
      actions: [
        IconButton(
          onPressed: () => auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Daftar sebagai owner atau karyawan'),
        const SizedBox(height: 20),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nama lengkap'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Nomor HP'),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'Owner',
              label: Text('Owner'),
              icon: Icon(Icons.store),
            ),
            ButtonSegment(
              value: 'Karyawan',
              label: Text('Karyawan'),
              icon: Icon(Icons.badge),
            ),
          ],
          selected: {role},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() => role = v.first),
        ),
        const SizedBox(height: 16),
        const Text(
          'Karyawan akan terhubung ke toko yang mengundang email akunnya setelah email terverifikasi.',
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                    message(c, 'Isi nama dan nomor HP.');
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await call('completeProfile', {
                      'name': name.text.trim(),
                      'phone': phone.text.trim(),
                      'role': role,
                    });
                  } catch (e) {
                    if (c.mounted) message(c, errorText(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Menyimpan…' : 'Mulai'),
        ),
      ],
    ),
  );
}
