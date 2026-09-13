import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/layer/layers_manager.dart';

Widget customAppBarLeading({required String label}) {
  return IconButton(
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
    onPressed: () => layersManager.popDetail(label),
  );
}
