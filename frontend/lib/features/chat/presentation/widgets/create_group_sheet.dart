import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../../friends/data/models/friend.dart';
import '../../../friends/data/services/friendship_service.dart';
import '../../../user/presentation/widgets/user_avatar.dart';
import '../../data/models/chat.dart';
import '../../data/services/chat_service.dart';

class CreateGroupSheet extends StatefulWidget {
  final void Function(Chat group) onCreated;

  const CreateGroupSheet({super.key, required this.onCreated});

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final ChatService _chatService = ChatService();
  final FriendshipService _friendshipService = FriendshipService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _avatarController = TextEditingController();

  List<Friend> _friends = [];
  final Set<int> _selectedIds = {};
  bool _isLoadingFriends = true;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final auth = context.read<AuthNotifier>();
    if (auth.userId == null || auth.token == null) return;
    final friends = await _friendshipService.getFriends(
      userId: auth.userId!,
      token: auth.token!,
    );
    if (mounted) {
      setState(() {
        _friends = friends;
        _isLoadingFriends = false;
      });
    }
  }

  void _showEmojiSheet(TextEditingController ctrl) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 300,
        child: EmojiPicker(
          textEditingController: ctrl,
          config: AppTheme.emojiPickerConfig(colors, height: 300),
        ),
      ),
    );
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = "Введите название группы");
      return;
    }
    if (_selectedIds.length < 2) {
      setState(() => _errorMessage = "Выберите минимум 2 участника");
      return;
    }

    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final group = await _chatService.createGroup(
      name: name,
      memberIds: _selectedIds.toList(),
      avatar: _avatarController.text.trim(),
      token: token,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (group != null) {
      Navigator.of(context).pop();
      widget.onCreated(group);
    } else {
      setState(() => _errorMessage = "Не удалось создать группу");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text("Новая группа",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: _inputDecoration(colors, "Название группы *").copyWith(
              suffixIcon: IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                onPressed: () => _showEmojiSheet(_nameController),
              ),
            ),
            maxLength: 100,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _avatarController,
            style: TextStyle(color: colors.textPrimary),
            decoration: _inputDecoration(colors, "Эмодзи аватар (необязательно)"),
            maxLength: 2,
          ),
          const SizedBox(height: 12),
          Text(
            "Участники (${_selectedIds.length} выбрано, мин. 2)",
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (_isLoadingFriends)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accentIndigo),
            ))
          else if (_friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text("У вас пока нет друзей",
                  style: TextStyle(
                      fontSize: 13, color: colors.textSecondary)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _friends.length,
                itemBuilder: (context, i) {
                  final friend = _friends[i];
                  final isSelected = _selectedIds.contains(friend.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: _selectedIds.length >= 14 && !isSelected
                        ? null
                        : (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(friend.id);
                              } else {
                                _selectedIds.remove(friend.id);
                              }
                            });
                          },
                    activeColor: AppTheme.accentIndigo,
                    title: Text(friend.username,
                        style: TextStyle(
                            fontSize: 14, color: colors.textPrimary)),
                    secondary: UserAvatar(
                      avatarUrl: friend.avatarUrl,
                      initial: friend.username.isNotEmpty ? friend.username[0] : '?',
                      radius: 18,
                      bgColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
                      textColor: AppTheme.accentIndigo,
                    ),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                },
              ),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCreating ? null : _handleCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentIndigo,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("Создать",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(AppColors colors, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      counterStyle:
          TextStyle(color: colors.textSecondary, fontSize: 11),
    );
  }
}
