import 'package:flutter/widgets.dart';

import '../presentation/viewmodels/sdk_view_model.dart';
import 'sdk_factory.dart';

class DependencyInjection extends InheritedWidget {
  DependencyInjection({super.key, required super.child})
    : sdkViewModel = SdkViewModel(factory: const SdkFactory());

  final SdkViewModel sdkViewModel;

  static DependencyInjection of(BuildContext context) {
    final DependencyInjection? result = context
        .dependOnInheritedWidgetOfExactType<DependencyInjection>();
    assert(result != null, 'DependencyInjection not found in widget tree');
    return result!;
  }

  @override
  bool updateShouldNotify(covariant DependencyInjection oldWidget) {
    return oldWidget.sdkViewModel != sdkViewModel;
  }
}
