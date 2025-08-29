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
      ),
      home: const LockScreen(),
    );
  }
}

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
    final bool canCheckBiometrics = await auth.canCheckBiometrics;
    final bool isBiometricSupported = await auth.isDeviceSupported();

    if (canCheckBiometrics && isBiometricSupported) {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Verifique sua identidade para acessar o app',
        options: const AuthenticationOptions(biometricOnly: true),
      );

      if (didAuthenticate) {
        setState(() => _isAuthenticated = true);
      } else {
        _showPinFallback();
      }
    } else {
      _showPinFallback();
    }
  } catch (e) {
    _showPinFallback();
  }
}

void _showPinFallback() async {
  final pin = await showDialog<String>(
    context: context,
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
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
    setState(() => _isAuthenticated = true);
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
      // Navega para HomePage quando autenticado
      Future.microtask(() {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      });
    }
    return const Scaffold(
      body: Center(child: Text("Verificando identidade...")),
    );
  }
}


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _serviceController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedFolder = "Outros";

  List<Map<String, String>> _credentials = [];
  List<String> _folders = ["Streamings", "Jogos", "Bancos", "Outros"];

  // chave fixa de exemplo (16 bytes = AES-128)
  final _key = encrypt.Key.fromUtf8('1234567890abcdef');
  final _iv = encrypt.IV.fromLength(16);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final credData = prefs.getString('credentials');
    if (credData != null) {
      final decoded = jsonDecode(credData) as List;
      _credentials = List<Map<String, String>>.from(decoded);
    }

    final folderData = prefs.getStringList('folders');
    if (folderData != null) {
      _folders = folderData;
    }

    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('credentials', jsonEncode(_credentials));
    await prefs.setStringList('folders', _folders);
  }

  String _encrypt(String text) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    return encrypter.encrypt(text, iv: _iv).base64;
  }

  String _decrypt(String text) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    return encrypter.decrypt64(text, iv: _iv);
  }

  void _addCredential() {
    final service = _serviceController.text;
    final login = _loginController.text;
    final password = _passwordController.text;

    if (service.isEmpty || login.isEmpty || password.isEmpty) return;

    final encryptedPassword = _encrypt(password);

    setState(() {
      _credentials.add({
        'folder': _selectedFolder,
        'service': service,
        'login': login,
        'password': encryptedPassword,
      });
    });

    _saveData();
    _serviceController.clear();
    _loginController.clear();
    _passwordController.clear();
  }

  void _addFolderDialog() {
    final folderController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Nova Pasta"),
        content: TextField(
          controller: folderController,
          decoration: const InputDecoration(hintText: "Nome da pasta"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (folderController.text.isNotEmpty) {
                setState(() {
                  _folders.add(folderController.text);
                  _selectedFolder = folderController.text;
                });
                _saveData();
              }
              Navigator.pop(context);
            },
            child: const Text("Adicionar"),
          ),
        ],
      ),
    );
  }

  void _removeFolder(String folder) {
    if (folder == "Outros") return; // Pasta padrão não pode ser removida

    setState(() {
      _folders.remove(folder);
      _credentials.removeWhere((item) => item['folder'] == folder);
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciador de Senhas'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (folder) => _removeFolder(folder),
            itemBuilder: (context) => _folders
                .where((f) => f != "Outros")
                .map((f) => PopupMenuItem(
                      value: f,
                      child: Text("Remover pasta: $f"),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Campos de entrada
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
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedFolder,
                    items: _folders
                        .map((f) =>
                            DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFolder = value!;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: "Pasta",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addFolderDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _addCredential,
              child: const Text('Salvar'),
            ),
            const SizedBox(height: 24),

            // Lista
            Expanded(
              child: ListView.builder(
                itemCount: _credentials.length,
                itemBuilder: (context, index) {
                  final item = _credentials[index];
                  bool _obscure = true;

                  return StatefulBuilder(
                    builder: (context, setLocalState) => Card(
                      child: ListTile(
                        title: Text("${item['service']} (${item['folder']})"),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Login: ${item['login']}"),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _obscure
                                        ? "Senha: ******"
                                        : "Senha: ${_decrypt(item['password']!)}",
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off),
                                  onPressed: () {
                                    setLocalState(() {
                                      _obscure = !_obscure;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(
                                        text:
                                            _decrypt(item['password']!),
                                      ),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text("Senha copiada!"),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
