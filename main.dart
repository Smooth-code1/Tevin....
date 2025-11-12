// lib/main.dart
// Full single-file CleaningPro app: polished home UI + Firebase Auth + Firestore booking system.
// Requirements:
//  - Add android/app/google-services.json (Firebase Android config)
//  - Add firebase_options.dart if using FlutterFire CLI and uncomment options init
//
// Dependencies required (see pubspec.yaml below)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:intl/intl.dart';

// If you generated firebase_options.dart using FlutterFire CLI, uncomment and use:
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // If you have firebase_options.dart, use:
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Firebase.initializeApp();
  runApp(const CleaningProApp());
}

class CleaningProApp extends StatelessWidget {
  const CleaningProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BookingProvider()),
      ],
      child: MaterialApp(
        title: 'CleaningPro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: GoogleFonts.poppins().fontFamily,
          primarySwatch: Colors.cyan,
          scaffoldBackgroundColor: const Color(0xFF0F0F1E),
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

/* ------------------ Splash ------------------ */
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget splash;
    try {
      splash = Lottie.asset('assets/lottie/cleaning.json', width: 200, height: 200);
    } catch (_) {
      splash = const Icon(Icons.cleaning_services, size: 140, color: Colors.cyanAccent);
    }
    return AnimatedSplashScreen(
      splash: splash,
      nextScreen: const AuthWrapper(),
      splashTransition: SplashTransition.fadeTransition,
      backgroundColor: const Color(0xFF0F0F1E),
      duration: 2000,
    );
  }
}

/* ----------------- Auth Wrapper ----------------- */
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snap.hasData && snap.data != null) return const RoleRouter();
        return const LoginScreen();
      },
    );
  }
}

/* ----------------- Role Router ----------------- */
class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});
  Future<String> _getRole(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return 'customer';
    final d = doc.data();
    if (d == null) return 'customer';
    return (d['role'] as String?) ?? 'customer';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();
    return FutureBuilder<String>(
      future: _getRole(user.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final role = snap.data ?? 'customer';
        if (role == 'admin') return const AdminDashboard();
        if (role == 'employee') return const EmployeeDashboard();
        return const CustomerDashboard();
      },
    );
  }
}

/* ================= AUTH PROVIDER ================= */
class AuthProvider with ChangeNotifier {
  String? _role;
  String? get role => _role;

  Future<void> signUp(String email, String password, String role) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
    await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
      'email': email,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _role = role;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    _role = null;
    notifyListeners();
  }
}

/* ================ BOOKING PROVIDER ================ */
class BookingProvider with ChangeNotifier {
  Future<void> createBooking(Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('bookings').add({
      ...data,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }
}

/* =================== LOGIN / SIGNUP =================== */
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool loading = false;

  @override void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _showSignUp() async {
    final _sEmail = TextEditingController();
    final _sPass = TextEditingController();
    String chosen = 'customer';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1E),
        title: const Text('Create Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _sEmail, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            TextField(controller: _sPass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 8),
            DropdownButton<String>(value: chosen, items: ['customer','employee'].map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
              onChanged: (v) => setState(() => chosen = v ?? 'customer')),
            const SizedBox(height: 8),
            const Text('Admin accounts are created by admins on server.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            try {
              await context.read<AuthProvider>().signUp(_sEmail.text.trim(), _sPass.text.trim(), chosen);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created')));
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }, child: const Text('Sign up')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: GlassmorphicContainer(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('CleaningPro', style: GoogleFonts.poppins(fontSize: 36, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                TextField(controller: _email, decoration: const InputDecoration(prefixIcon: Icon(Icons.email), labelText: 'Email')),
                const SizedBox(height: 8),
                TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.lock), labelText: 'Password')),
                const SizedBox(height: 14),
                ElevatedButton(onPressed: () async {
                  setState(() => loading = true);
                  try {
                    await context.read<AuthProvider>().login(_email.text.trim(), _pass.text.trim());
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  } finally {
                    if (mounted) setState(() => loading = false);
                  }
                }, child: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login')),
                TextButton(onPressed: _showSignUp, child: const Text('Create account')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/* =================== CUSTOMER DASHBOARD (Advanced UI) =================== */
class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});
  @override State<CustomerDashboard> createState() => _CustomerDashboardState();
}
class _CustomerDashboardState extends State<CustomerDashboard> {
  final List<Map<String,dynamic>> services = [
    {'title':'House Cleaning','price':'\$9.99','icon':Icons.home},
    {'title':'Office Cleaning','price':'\$24.99','icon':Icons.business},
    {'title':'Deep Cleaning','price':'\$49.99','icon':Icons.cleaning_services},
    {'title':'Carpet Cleaning','price':'\$14.99','icon':Icons.format_paint},
    {'title':'Window Cleaning','price':'\$19.99','icon':Icons.window},
  ];
  String query = '';
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final displayed = services.where((s) {
      final q = query.toLowerCase();
      if (q.isNotEmpty && !s['title'].toString().toLowerCase().contains(q)) return false;
      if (filter != 'all' && s['title'] != filter) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          IconButton(onPressed: () => context.read<AuthProvider>().logout(), icon: const Icon(Icons.logout)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllBookings())), icon: const Icon(Icons.list_alt))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          // Search & filters
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search services', filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              onSelected: (v) => setState(() => filter = v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('All')),
                for (var s in services) PopupMenuItem(value: s['title'], child: Text(s['title']))
              ],
            )
          ]),
          const SizedBox(height: 12),
          // cards grid
          Expanded(
            child: GridView.builder(
              itemCount: displayed.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.9),
              itemBuilder: (context, i) {
                final s = displayed[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingScreen(service: s['title'], price: s['price']))),
                  child: NeuCard(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(s['icon'], size: 44, color: Colors.cyanAccent),
                    const SizedBox(height: 8),
                    Text(s['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(s['price']),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingScreen(service: s['title'], price: s['price']))), child: const Text('Book'))
                  ])),
                );
              },
            ),
          )
        ]),
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())), child: const Icon(Icons.add)),
    );
  }
}

/* ================= EMPLOYEE DASHBOARD ================= */
class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Panel'),
        actions: [IconButton(onPressed: () => context.read<AuthProvider>().logout(), icon: const Icon(Icons.logout))],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bookings').where('status', isEqualTo: 'pending').snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No pending bookings'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String,dynamic>;
            final id = docs[i].id;
            return NeuCard(child: ListTile(
              title: Text(d['service'] ?? 'Service'),
              subtitle: Text('${d['address'] ?? 'address'} \n${formatTimestamp(d['date'])}'),
              trailing: ElevatedButton(onPressed: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                await docs[i].reference.update({'status':'accepted','employeeId':uid});
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accepted')));
              }, child: const Text('Accept')),
            ));
          });
        },
      ),
    );
  }
}

/* ================= ADMIN DASHBOARD ================= */
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel'), actions: [IconButton(onPressed: () => context.read<AuthProvider>().logout(), icon: const Icon(Icons.logout))]),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          Row(children: [
            Expanded(child: _statCard('Total Bookings', '...')),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Active Employees','...')),
          ]),
          const SizedBox(height: 12),
          Expanded(child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('bookings').orderBy('createdAt', descending: true).snapshots(),
            builder: (ctx,snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              return ListView.builder(itemCount: docs.length, itemBuilder: (_,i){
                final d = docs[i].data() as Map<String,dynamic>;
                final status = d['status'] ?? '';
                return NeuCard(child: ListTile(
                  title: Text(d['service'] ?? 'Service'),
                  subtitle: Text('Customer: ${d['customerId'] ?? ''}\nStatus: $status\nDate: ${formatTimestamp(d['date'])}'),
                ));
              });
            },
          ))
        ]),
      ),
    );
  }
  Widget _statCard(String t, String v) => NeuCard(child: ListTile(leading: Icon(Icons.analytics, color: Colors.amber), title: Text(t), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.bold))));
}

/* ================= BOOKING SCREEN (Form) ================= */
class BookingScreen extends StatefulWidget {
  final String? service;
  final String? price;
  const BookingScreen({super.key, this.service, this.price});
  @override State<BookingScreen> createState() => _BookingScreenState();
}
class _BookingScreenState extends State<BookingScreen> {
  final _address = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool loading = false;

  @override void dispose() { _address.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final sel = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(DateTime.now().year+2));
    if (sel != null) setState(() => _date = sel);
  }
  Future<void> _pickTime() async {
    final sel = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (sel != null) setState(() => _time = sel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.service ?? 'Book Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: GlassmorphicContainer(child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Text(widget.service ?? 'Select Service', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Full Address', prefixIcon: Icon(Icons.location_on))),
            const SizedBox(height: 8),
            ListTile(title: Text(_date==null ? 'Pick Date' : DateFormat('yyyy-MM-dd').format(_date!)), trailing: const Icon(Icons.calendar_today), onTap: _pickDate),
            ListTile(title: Text(_time==null ? 'Pick Time' : _time!.format(context)), trailing: const Icon(Icons.access_time), onTap: _pickTime),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid==null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in'))); return; }
              if (_date==null || _time==null || _address.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields'))); return; }
              setState(() => loading = true);
              final dt = DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
              try {
                await context.read<BookingProvider>().createBooking({
                  'service': widget.service ?? 'Unknown',
                  'price': widget.price ?? '0',
                  'address': _address.text.trim(),
                  'date': Timestamp.fromDate(dt),
                  'customerId': uid,
                });
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking Confirmed')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              } finally { if (mounted) setState(() => loading = false); }
            }, child: loading ? const CircularProgressIndicator() : const Text('Confirm Booking'))
          ]),
        )),
      ),
    );
  }
}

/* ================= ALL BOOKINGS (Public) ================= */
class AllBookings extends StatelessWidget {
  const AllBookings({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Bookings')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bookings').orderBy('createdAt', descending: true).snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No bookings'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (_,i){
            final d = docs[i].data() as Map<String,dynamic>;
            return NeuCard(child: ListTile(title: Text(d['service'] ?? 'Service'), subtitle: Text('Status: ${d['status'] ?? ''}\nDate: ${formatTimestamp(d['date'])}')));
          });
        },
      ),
    );
  }
}

/* =================== UI Helpers =================== */
String formatTimestamp(dynamic t) {
  try {
    if (t is Timestamp) return DateFormat('yyyy-MM-dd HH:mm').format(t.toDate());
    if (t is DateTime) return DateFormat('yyyy-MM-dd HH:mm').format(t);
  } catch (_) {}
  return '';
}

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  const GlassmorphicContainer({super.key, required this.child});
  @override Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8,sigmaY:8),
      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue.withOpacity(0.03), Colors.purple.withOpacity(0.03)])), child: child)));
  }
}

class NeuCard extends StatelessWidget {
  final Widget child;
  const NeuCard({super.key, required this.child});
  @override Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0F0F1E), borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(offset: const Offset(8,8), color: Colors.black.withOpacity(0.45), blurRadius: 12), const BoxShadow(offset: Offset(-8,-8), color: Colors.white10, blurRadius: 12)]),
      child: child);
  }
}