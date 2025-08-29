import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:local_auth/local_auth.dart';

void main() {
  runApp(const GuardaSenhasApp());
}

class GuardaSenhasApp extends StatelessWidget {
  const GuardaSenhasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerenciador de Senhas',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        // NOVA COR DE FUNDO APLICADA A TODO O APP
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const LockScreen(),
    );
  }
}

// --- TELA DE BLOQUEIO (sem alterações) ---
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isAuthenticated = false;

  Future<void> _authenticate() async {
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Verifique sua identidade para acessar o app',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (mounted && didAuthenticate) {
        setState(() => _isAuthenticated = true);
      }
    } on PlatformException catch (e) {
      print('Erro de autenticação: $e');
      if (mounted) _showPinFallback();
    }
  }

  void _showPinFallback() async {
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Digite seu PIN'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'PIN'),
          ),
          actions: [
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Sair'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (pin == "1234") {
      if (mounted) setState(() => _isAuthenticated = true);
    } else {
      if (mounted) _authenticate();
    }
  }

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      Future.microtask(() {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      });
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// --- TELA PRINCIPAL (HomePage) ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  List<Map<String, String>> _credentials = [];
  List<Map<String, String>> _filteredCredentials = [];
  final Set<Map<String, String>> _visiblePasswords = {};
  final _key = encrypt.Key.fromUtf8('1234567890abcdef');

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterCredentials);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCredentials() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCredentials = _credentials;
      } else {
        _filteredCredentials = _credentials
            .where((cred) => cred['service']!.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final credData = prefs.getString('credentials');
    if (credData != null) {
      final decoded = jsonDecode(credData) as List;
      setState(() {
        _credentials = List<Map<String, String>>.from(
            decoded.map((item) => Map<String, String>.from(item)));
        _filteredCredentials = _credentials;
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('credentials', jsonEncode(_credentials));
  }

  String _encrypt(String text) {
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  String _decrypt(String text) {
    try {
      final parts = text.split(':');
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedText = parts[1];
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      return encrypter.decrypt64(encryptedText, iv: iv);
    } catch (e) {
      print("Erro ao descriptografar: $e");
      return "Erro de dados";
    }
  }

  void _addCredential(Map<String, String> newCredential) {
    final encryptedPassword = _encrypt(newCredential['password']!);
    setState(() {
      _credentials.add({
        'service': newCredential['service']!,
        'login': newCredential['login']!,
        'password': encryptedPassword,
      });
      _credentials.sort((a, b) => a['service']!.toLowerCase().compareTo(b['service']!.toLowerCase()));
    });
    _filterCredentials();
    _saveData();
  }

  void _removeCredential(Map<String, String> itemToRemove) {
    setState(() {
      _credentials.remove(itemToRemove);
      _visiblePasswords.remove(itemToRemove);
      _filterCredentials();
    });
    _saveData();
  }

  void _navigateToAndAddCredential(BuildContext context) async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (context) => const AddCredentialScreen()),
    );
    if (result != null) {
      _addCredential(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suas Senhas'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Pesquisar por serviço',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredCredentials.isEmpty
                  ? const Center(child: Text("Nenhuma senha salva."))
                  : ListView.builder(
                      itemCount: _filteredCredentials.length,
                      itemBuilder: (context, index) {
                        final item = _filteredCredentials[index];
                        final bool isObscure = !_visiblePasswords.contains(item);
                        return Card(
                          child: ListTile(
                            title: Text(item['service']!),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Login: ${item['login']}"),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isObscure
                                            ? "Senha: ******"
                                            : "Senha: ${_decrypt(item['password']!)}",
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(isObscure ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () => setState(() {
                                        if (isObscure) {
                                          _visiblePasswords.add(item);
                                        } else {
                                          _visiblePasswords.remove(item);
                                        }
                                      }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: _decrypt(item['password']!)));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Senha copiada!")),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () => _removeCredential(item),
                                    )
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAndAddCredential(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// --- NOVA TELA PARA ADICIONAR SENHAS (AddCredentialScreen) ---
class AddCredentialScreen extends StatefulWidget {
  const AddCredentialScreen({super.key});

  @override
  State<AddCredentialScreen> createState() => _AddCredentialScreenState();
}

class _AddCredentialScreenState extends State<AddCredentialScreen> {
  final _serviceController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordObscured = true;

  void _saveCredential() {
    if (_serviceController.text.isNotEmpty &&
        _loginController.text.isNotEmpty &&
        _passwordController.text.isNotEmpty) {
      final newCredential = {
        'service': _serviceController.text,
        'login': _loginController.text,
        'password': _passwordController.text, // Senha em texto plano
      };
      // Retorna os dados para a HomePage
      Navigator.of(context).pop(newCredential);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Nova Senha'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _serviceController,
              decoration: const InputDecoration(
                labelText: 'Serviço',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Senha',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_isPasswordObscured
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _isPasswordObscured = !_isPasswordObscured;
                    });
                  },
                ),
              ),
              obscureText: _isPasswordObscured,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveCredential,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}