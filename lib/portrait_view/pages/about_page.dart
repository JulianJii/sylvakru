part of '../../layer/about_layer.dart';

extension _AboutPage on _AboutLayerState {
  Widget pageView(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          customAppBar(context),
          SizedBox(height: 10),
          Expanded(child: content()),
        ],
      ),
    );
  }

  PreferredSizeWidget customAppBar(BuildContext context) {
    return MyAppBar.detail(
      backLabel: 'settings',
      title: AppLocalizations.of(context).about,
    );
  }
}
