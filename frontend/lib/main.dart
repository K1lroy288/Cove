import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF5865F2),
        scaffoldBackgroundColor: const Color(0xFF36393F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF202225),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF5865F2), width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5865F2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const AuthScreen(),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Контроллеры
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;      // true = Вход, false = Регистрация
  bool _isLoading = false;
  String? _statusMessage;    // Для сообщений об успехе или ошибке
  bool _isSuccess = false;   // Флаг цвета сообщения (зеленый/красный)

  // 1. Валидация Имени пользователя
  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) return 'Введите имя пользователя';
    if (value.length < 3) return 'Минимум 3 символа';
    return null;
  }

  // 2. Валидация Пароля
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Введите пароль';
    if (value.length < 6) return 'Минимум 6 символов';
    return null;
  }

  // 3. Валидация Подтверждения
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Повторите пароль';
    if (value != _passwordController.text) return 'Пароли не совпадают';
    return null;
  }

  // 4. Обработка отправки
  Future<void> _handleSubmit() async {
    // Проверяем валидность всех полей
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _statusMessage = null;
        _isSuccess = false;
      });

      // Имитация запроса к серверу (2 секунды)
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _isLoading = false;
        
        // Логика переключения после регистрации
        if (!_isLogin) {
          _statusMessage = '✅ Регистрация успешна! Теперь войдите.';
          _isSuccess = true;
          _isLogin = true; // <-- Переключаем на форму входа
          _formKey.currentState!.reset(); // Очищаем форму
          _usernameController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
        } else {
          // Логика для входа
          _statusMessage = '✅ Вход выполнен! Переход в чат...';
          _isSuccess = true;
          // Тут позже будет переход на главный экран:
          // Navigator.pushReplacement(..., MaterialPageRoute(builder: (context) => MainScreen()));
        }
      });
      
      print(' Данные отправлены: user=${_usernameController.text}');
    }
  }

  // Переключение режимов
  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _statusMessage = null;
      _formKey.currentState?.reset();
      _usernameController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: const Color(0xFF2F3136),
              // ✅ FIX 1: Ограничиваем ширину формы
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isLogin ? 'Вход в аккаунт' : 'Регистрация',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? 'Рады видеть вас снова!' : 'Создайте аккаунт',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 24),

                      // ✅ FIX 3: Поле Username
                      TextFormField(
                        controller: _usernameController,
                        keyboardType: TextInputType.text,
                        // ✅ FIX 2: Валидация только по кнопке (disabled), чтобы ошибки не висели при удалении текста
                        autovalidateMode: AutovalidateMode.disabled,
                        validator: _validateUsername,
                        decoration: const InputDecoration(
                          labelText: 'Имя пользователя',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        autovalidateMode: AutovalidateMode.disabled,
                        validator: _validatePassword,
                        decoration: const InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          autovalidateMode: AutovalidateMode.disabled,
                          validator: _validateConfirmPassword,
                          decoration: const InputDecoration(
                            labelText: 'Подтвердите пароль',
                            prefixIcon: Icon(Icons.lock_reset),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(_isLogin ? 'Войти' : 'Создать аккаунт'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_statusMessage != null)
                        Text(
                          _statusMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 16),

                      TextButton(
                        onPressed: _toggleMode,
                        child: Text(_isLogin ? 'Нет аккаунта? Зарегистрироваться' : 'Уже есть аккаунт? Войти'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}