import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/services/auth_service.dart';
import '../../dashboard/presentation/main_dashboard_screen.dart';
import '../../../shared/services/auth_notifier.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Контроллеры для полей ввода
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Состояние формы
  bool _isLogin = true;           // true = Вход, false = Регистрация
  bool _isLoading = false;        // Индикатор загрузки
  String? _statusMessage;         // Текст сообщения (ошибка/успех)
  bool _isSuccess = false;        // Цвет сообщения: зелёный/красный

  // 🔍 Валидация имени пользователя
  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите имя пользователя';
    }
    
    // Убираем пробелы по краям для проверки
    final trimmed = value.trim();
    
    if (trimmed.length < 3) {
      return 'Минимум 3 символа';
    }
    
    if (trimmed.length > 32) {
      return 'Максимум 32 символа';
    }
    
    // ✅ Разрешаем: латиница, кириллица, цифры, _, -, .
    // ❌ Блокируем: спецсимволы, пробелы внутри, опасные паттерны
    if (!RegExp(r'^[a-zA-Zа-яА-ЯёЁ0-9_\-.]+$').hasMatch(trimmed)) {
      return 'Разрешены только буквы, цифры, _, - и .';
    }
    
    return null;
  }

  // 🔍 Валидация пароля
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите пароль';
    }
    if (value.length < 6) {
      return 'Минимум 6 символов';
    }
    return null;
  }

  // 🔍 Валидация подтверждения пароля
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Повторите пароль';
    }
    if (value != _passwordController.text) {
      return 'Пароли не совпадают';
    }
    return null;
  }

  // 🚀 Обработка отправки формы
  Future<void> _handleSubmit() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isLoading = true;
    _statusMessage = null;
    _isSuccess = false;
  });

  try {
    final authService = AuthService();

    if (_isLogin) {
      // === ЛОГИН ===
      final response = await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      // 🔥 1. Сохраняем данные в глобальное состояние
      // Получаем экземпляр AuthNotifier через context и вызываем login()
      Provider.of<AuthNotifier>(context, listen: false).login(
        response.username, 
        response.token
      );

      // 2. Переходим на дашборд
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainDashboardScreen()),
        );
      }
    } else {
      // === РЕГИСТРАЦИЯ ===
      // Важно: register() возвращает void, поэтому НЕ присваиваем результат
      await authService.register(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        setState(() {
          _statusMessage = '✅ Аккаунт создан! Теперь войдите.';
          _isSuccess = true;
          _isLogin = true;
          _formKey.currentState?.reset();
          _usernameController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _statusMessage = '❌ ${e.toString().replaceFirst('Exception: ', '')}';
        _isSuccess = false;
      });
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  // 💾 Сохранение токена (заглушка)
  void _saveToken(String token) {
    print('🔑 Токен получен: $token');
    // TODO: В продакшене использовать flutter_secure_storage:
    // final storage = FlutterSecureStorage();
    // await storage.write(key: 'auth_token', value: token);
  }

  // 🔄 Переключение между Входом и Регистрацией
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

  // 🧹 Очистка ресурсов при уничтожении виджета
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Заголовок
                      Text(
                        _isLogin ? 'Вход в аккаунт' : 'Регистрация',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? 'Рады видеть вас снова!' : 'Создайте аккаунт, чтобы начать',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 24),

                      // Поле: Имя пользователя
                      TextFormField(
                        controller: _usernameController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.disabled,
                        validator: _validateUsername,
                        decoration: const InputDecoration(
                          labelText: 'Имя пользователя',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Поле: Пароль
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                        autovalidateMode: AutovalidateMode.disabled,
                        validator: _validatePassword,
                        decoration: const InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Поле: Подтверждение пароля (только при регистрации)
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autovalidateMode: AutovalidateMode.disabled,
                          validator: _validateConfirmPassword,
                          decoration: const InputDecoration(
                            labelText: 'Подтвердите пароль',
                            prefixIcon: Icon(Icons.lock_reset),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Кнопка отправки
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

                      // Сообщение об успехе/ошибке
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

                      // Переключатель режима
                      TextButton(
                        onPressed: _toggleMode,
                        child: Text(
                          _isLogin ? 'Нет аккаунта? Зарегистрироваться' : 'Уже есть аккаунт? Войти',
                        ),
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