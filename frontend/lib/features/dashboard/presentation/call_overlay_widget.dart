import 'package:flutter/material.dart';

class CallOverlayWidget extends StatelessWidget {
  final VoidCallback onEndCall;

  const CallOverlayWidget({super.key, required this.onEndCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF202225).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5865F2), width: 2),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: const [
                Icon(Icons.call, color: Color(0xFF5865F2)),
                SizedBox(width: 12),
                Text('Голосовой звонок', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Spacer(),
                Text('02:14', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: 4,
              itemBuilder: (context, index) => Container(
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('User ${index + 1}', style: const TextStyle(color: Colors.white))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallButton(icon: Icons.mic, label: 'Микрофон'),
                const SizedBox(width: 16),
                _CallButton(icon: Icons.videocam, label: 'Камера'),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: onEndCall,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                  child: const Text('Завершить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CallButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(onPressed: () {}, icon: Icon(icon), style: IconButton.styleFrom(backgroundColor: Colors.grey[700])),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}