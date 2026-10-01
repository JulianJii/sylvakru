import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/scale_widget.dart';

class MySwitch extends StatelessWidget {
  final String? trueText;
  final String? falseText;
  final ValueNotifier<bool> valueNotifier;
  final void Function()? onToggleCallBack;
  final bool inLyricsPage;

  const MySwitch({
    super.key,
    this.trueText,
    this.falseText,
    required this.valueNotifier,
    this.onToggleCallBack,
    this.inLyricsPage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (trueText == null) {
      return switcher();
    }
    return Row(
      mainAxisSize: .min,
      children: [
        ValueListenableBuilder(
          valueListenable: valueNotifier,
          builder: (context, value, child) {
            return Text(
              value ? trueText! : falseText!,
              style: TextStyle(
                color: inLyricsPage ? lyricsPageForegroundColor.value : null,
              ),
            );
          },
        ),
        SizedBox(width: 5),
        switcher(),
      ],
    );
  }

  Widget switcher() {
    return ValueListenableBuilder(
      valueListenable: valueNotifier,
      builder: (context, value, child) {
        return ValueListenableBuilder(
          valueListenable: switchColor.valueNotifier,
          builder: (_, _, _) {
            return ScaleWidget(
              // ponytail: M3 Switch 是 52x32，缩放只为对齐原来的 45x20 尺寸，
              // 想改大小就调这里。
              child: Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: value,
                  activeTrackColor: switchColor.value,
                  activeThumbColor: Colors.white,
                  inactiveTrackColor: Colors.grey.shade300,
                  inactiveThumbColor: Colors.white,
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) {
                    tryVibrate();
                    valueNotifier.value = value;
                    onToggleCallBack?.call();
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
