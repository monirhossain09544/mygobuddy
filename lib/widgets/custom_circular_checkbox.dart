import 'package:flutter/material.dart';

class CustomCircularCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget label;
  final Color activeColor;

  const CustomCircularCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        onChanged(!value);
      },
      // Use a transparent splash color for better feedback without visual clutter
      child: InkWell(
        splashColor: activeColor.withOpacity(0.2),
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          onChanged(!value);
        },
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? activeColor : Colors.transparent,
                border: Border.all(
                  color: value ? activeColor : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 16,
              )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: label),
          ],
        ),
      ),
    );
  }
}
