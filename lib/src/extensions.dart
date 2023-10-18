import 'package:collection/collection.dart';

extension RemoveWhereAndReturn<T> on List<T> {
  T? removeWhereAndReturn(bool Function(T element) test) {
    var el = firstWhereOrNull(test);
    remove(el);
    return el;
  }
}
