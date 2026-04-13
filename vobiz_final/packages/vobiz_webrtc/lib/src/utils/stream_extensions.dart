import 'dart:async';

extension StreamControllerX<T> on StreamController<T> {
  void addIfOpen(T event) {
    if (!isClosed) {
      add(event);
    }
  }
}
